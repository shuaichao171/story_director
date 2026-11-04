"""等待剧情导演模组的 START/STOP 信号，用 ffmpeg 录制《饥荒联机版》窗口画面和系统声音。

一般不用直接运行本脚本，用 tools/shoot.py 一条命令完成启用模组、建片场世界、开拍和录制。
单独使用（游戏已在片场世界里）：
    python tools/record.py --play sample --out takes/sample.mp4

模组在 client_save 下写 "START <场景名> <时间戳>" / "STOP ..."（开拍失败时写 "ERROR <原因>"）。
脚本只响应启动后新写入的信号。--play 会先写 client_save/story_director_cmd，让已进入世界的游戏立即开拍。
client_save 目录、ffmpeg 不指定时自动查找。
画面默认用 Windows 图形捕获（ffmpeg gfxcapture，需要 FFmpeg 8 以上）直接抓游戏窗口，被挡住也不影响；
ffmpeg 不支持时自动改为录屏幕上游戏窗口所在区域（gdigrab），录制期间窗口不能被遮挡。
声音用 soundcard 录默认扬声器的回环（会录进此时电脑上所有声音），--no-audio 关闭。
画面和声音分开录，停止时同一刻结束，按两者的结束时刻对齐后合成。
"""

import argparse
import ctypes
import ctypes.wintypes as wt
import glob
import os
import re
import shutil
import subprocess
import sys
import threading
import time
import uuid
import wave

WINDOW_TITLE = "Don't Starve Together"
SAMPLE_RATE = 48000
SIGNAL_FILE = "story_director_signal"
COMMAND_FILE = "story_director_cmd"
# Steam 正式版、测试版、WeGame 版各自的存档根目录
KLEI_GAME_DIRS = ("DoNotStarveTogether", "DoNotStarveTogetherBetaBranch", "DoNotStarveTogetherRail")


# ---------------------------------------------------------------------------
# 自动查找：存档目录、ffmpeg

def documents_dir():
    """当前用户的“文档”目录（支持被移到其他盘的情况）。"""

    class GUID(ctypes.Structure):
        _fields_ = [("Data1", wt.DWORD), ("Data2", wt.WORD), ("Data3", wt.WORD), ("Data4", ctypes.c_ubyte * 8)]

    u = uuid.UUID("FDD39AD0-238F-46AF-ADB4-6C85480369C7")  # FOLDERID_Documents
    guid = GUID(u.fields[0], u.fields[1], u.fields[2], (ctypes.c_ubyte * 8)(*u.bytes[8:]))
    path = ctypes.c_wchar_p()
    try:
        if ctypes.windll.shell32.SHGetKnownFolderPath(ctypes.byref(guid), 0, None, ctypes.byref(path)) == 0:
            result = path.value
            ctypes.windll.ole32.CoTaskMemFree(path)
            return result
    except (AttributeError, OSError):
        pass
    return os.path.join(os.path.expanduser("~"), "Documents")


def find_save_dirs():
    """所有账号的 client_save 目录，最近用过的排在前面。"""
    found = []
    for game in KLEI_GAME_DIRS:
        for d in glob.glob(os.path.join(documents_dir(), "Klei", game, "*", "client_save")):
            if os.path.isdir(d):
                found.append(d)

    def last_used(d):
        times = [os.path.getmtime(d)]
        times += [os.path.getmtime(f) for f in glob.glob(os.path.join(d, "*")) if os.path.isfile(f)]
        return max(times)

    return sorted(found, key=last_used, reverse=True)


def find_ffmpeg():
    """依次找：PATH、winget 安装目录、tools/ffmpeg/bin。"""
    exe = shutil.which("ffmpeg")
    if exe:
        return exe
    patterns = [
        os.path.join(os.environ.get("LOCALAPPDATA", ""), "Microsoft", "WinGet", "Packages", "*FFmpeg*", "*", "bin", "ffmpeg.exe"),
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "ffmpeg", "bin", "ffmpeg.exe"),
    ]
    for pattern in patterns:
        hits = sorted(glob.glob(pattern), reverse=True)
        if hits:
            return hits[0]
    return None


def ffmpeg_version(ffmpeg):
    out = subprocess.run([ffmpeg, "-hide_banner", "-version"], capture_output=True, text=True, errors="replace")
    first = out.stdout.splitlines()[0] if out.stdout else ""
    return first.replace("ffmpeg version ", "").split(" ")[0]


def has_gfxcapture(ffmpeg):
    out = subprocess.run([ffmpeg, "-hide_banner", "-filters"], capture_output=True, text=True, errors="replace")
    return re.search(r"\sgfxcapture\s", out.stdout) is not None


# ---------------------------------------------------------------------------
# 信号与指令

def read_signal(path):
    """返回去掉 SetPersistentString 文件头（"KLEI     1"）后的信号文本。"""
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            text = f.read()
    except OSError:
        return ""
    m = re.search(r"(START|STOP|ERROR)\b.*", text)
    return m.group(0).strip() if m else ""


def send_command(save_dir, command):
    """写入模组轮询的指令文件，让游戏开拍。"""
    with open(os.path.join(save_dir, COMMAND_FILE), "w", encoding="utf-8") as f:
        f.write(f"{command} {time.time():.0f}")


def wait_for(path, prefixes, baseline, deadline):
    while time.time() < deadline:
        text = read_signal(path)
        if text != baseline and text.startswith(prefixes):
            return text
        time.sleep(0.05)
    return None


# ---------------------------------------------------------------------------
# 游戏窗口

user32 = ctypes.windll.user32


def game_window():
    hwnd = user32.FindWindowW(None, WINDOW_TITLE)
    if not hwnd:
        raise RuntimeError("找不到游戏窗口：" + WINDOW_TITLE)
    return hwnd


def game_client_rect(hwnd):
    rect = wt.RECT()
    user32.GetClientRect(hwnd, ctypes.byref(rect))
    pt = wt.POINT(0, 0)
    user32.ClientToScreen(hwnd, ctypes.byref(pt))
    # yuv420p 要求宽高为偶数
    w = (rect.right - rect.left) // 2 * 2
    h = (rect.bottom - rect.top) // 2 * 2
    return pt.x, pt.y, w, h


# ---------------------------------------------------------------------------
# 录音

class LoopbackRecorder:
    """在后台线程录默认扬声器的回环声音，记录结束时刻用于和画面对齐。"""

    def __init__(self):
        import soundcard
        speaker = soundcard.default_speaker()
        self.mic = soundcard.get_microphone(id=str(speaker.name), include_loopback=True)
        self.chunks = []
        self.stop_event = threading.Event()
        self.end_time = None
        self.thread = threading.Thread(target=self._run, daemon=True)

    def start(self):
        self.thread.start()

    def _run(self):
        block = SAMPLE_RATE // 20
        with self.mic.recorder(samplerate=SAMPLE_RATE, channels=2) as rec:
            while not self.stop_event.is_set():
                self.chunks.append(rec.record(numframes=block))
            self.end_time = time.perf_counter()

    def stop(self):
        self.stop_event.set()
        self.thread.join(timeout=5)

    def save_wav(self, path):
        import numpy as np
        data = np.concatenate(self.chunks) if self.chunks else np.zeros((0, 2))
        pcm = (np.clip(data, -1, 1) * 32767).astype("<i2")
        with wave.open(path, "wb") as w:
            w.setnchannels(2)
            w.setsampwidth(2)
            w.setframerate(SAMPLE_RATE)
            w.writeframes(pcm.tobytes())
        return len(data) / SAMPLE_RATE


def probe_duration(ffmpeg, path):
    ffprobe = os.path.join(os.path.dirname(ffmpeg), "ffprobe.exe") if os.path.dirname(ffmpeg) else "ffprobe"
    out = subprocess.run(
        [ffprobe, "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
        capture_output=True, text=True, check=True)
    return float(out.stdout.strip())


# ---------------------------------------------------------------------------
# 录制

def record(save_dir, out, ffmpeg, fps=30, wait=900, max_length=600, capture="auto", audio=True, play=None,
           start_timeout_hint=None):
    """等 START 开录、等 STOP 收尾。返回 (退出码, 说明)：0 成功，1 超时强停，2 没开拍，3 游戏报错。"""
    try:
        ctypes.windll.shcore.SetProcessDpiAwareness(2)  # 按物理像素取窗口坐标，和 gdigrab 一致
    except (AttributeError, OSError):
        pass
    if capture == "auto":
        capture = "window" if has_gfxcapture(ffmpeg) else "screen"

    signal = os.path.join(save_dir, SIGNAL_FILE)
    baseline = read_signal(signal)
    if play:
        send_command(save_dir, "PLAY " + play)
        print("已发送开拍指令：", play, flush=True)
    print("等待游戏开拍……", flush=True)
    start = wait_for(signal, ("START", "ERROR"), baseline, time.time() + wait)
    if start is None:
        return 2, start_timeout_hint or "超时：没有收到开拍信号"
    if start.startswith("ERROR"):
        return 3, "游戏里开拍失败：" + re.sub(r"^ERROR\s+|\s+\d+$", "", start)

    hwnd = game_window()
    x, y, w, h = game_client_rect(hwnd)
    out = os.path.abspath(out)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    base, _ = os.path.splitext(out)
    video_path = base + ".video.mp4" if audio else out
    audio_path = base + ".audio.wav"

    if capture == "window":
        # Windows 图形捕获：直接抓游戏窗口内容，不受其他窗口遮挡
        print(f"开始录制：窗口捕获 {w}x{h}", flush=True)
        source = [
            "-filter_complex",
            f"gfxcapture=hwnd={hwnd}:capture_cursor=0:max_framerate={fps},"
            f"hwdownload,format=bgra,fps={fps},crop=trunc(iw/2)*2:trunc(ih/2)*2",
        ]
    else:
        # 屏幕区域捕获：录桌面上游戏窗口所在的区域，期间不能被遮挡
        print(f"开始录制：屏幕区域 {w}x{h} @ ({x},{y})，录制期间不要遮挡游戏窗口", flush=True)
        source = [
            "-f", "gdigrab", "-framerate", str(fps), "-draw_mouse", "0",
            "-offset_x", str(x), "-offset_y", str(y), "-video_size", f"{w}x{h}",
            "-i", "desktop",
        ]

    recorder = None
    if audio:
        recorder = LoopbackRecorder()
        recorder.start()

    cmd = [
        ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
        *source,
        "-c:v", "libx264", "-preset", "veryfast", "-crf", "18", "-pix_fmt", "yuv420p",
        "-movflags", "+faststart",
        video_path,
    ]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)

    stop = wait_for(signal, ("STOP",), start, time.time() + max_length)
    print("拍摄结束" if stop else "超过最长时长，强制停止", flush=True)
    # 画面和声音在同一刻停止，之后用各自时长反推起点
    video_end = time.perf_counter()
    proc.stdin.write(b"q")
    proc.stdin.flush()
    if recorder is not None:
        recorder.stop()
    try:
        proc.wait(timeout=30)
    except subprocess.TimeoutExpired:
        proc.kill()

    if recorder is not None:
        audio_len = recorder.save_wav(audio_path)
        video_len = probe_duration(ffmpeg, video_path)
        # 声音比画面早开始多少秒（正数则裁掉声音开头，负数则在声音前补静音）
        lead = (video_end - video_len) - (recorder.end_time - audio_len)
        print(f"画面 {video_len:.1f}s，声音 {audio_len:.1f}s，对齐偏移 {lead:+.3f}s", flush=True)
        if lead >= 0:
            audio_in = ["-ss", f"{lead:.3f}", "-i", audio_path]
            afilter = []
        else:
            audio_in = ["-i", audio_path]
            afilter = ["-af", f"adelay={int(-lead * 1000)}:all=1"]
        subprocess.run([
            ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
            "-i", video_path, *audio_in,
            "-map", "0:v", "-map", "1:a", *afilter,
            "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-shortest",
            "-movflags", "+faststart", out,
        ], check=True)
        os.remove(video_path)
        os.remove(audio_path)
    return (0 if stop else 1), "已保存：" + out


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser(description="录制剧情导演模组的一条拍摄")
    ap.add_argument("--out", required=True, help="输出的 mp4 路径")
    ap.add_argument("--save-dir", help="client_save 目录（默认自动查找最近用过的账号）")
    ap.add_argument("--signal", help=argparse.SUPPRESS)  # 旧参数：信号文件路径，等价于 --save-dir 其所在目录
    ap.add_argument("--ffmpeg", help="ffmpeg.exe 路径（默认自动查找）")
    ap.add_argument("--fps", type=int, default=30)
    ap.add_argument("--wait", type=float, default=900, help="等待开拍的最长秒数")
    ap.add_argument("--max-length", type=float, default=600, help="单条录像最长秒数")
    ap.add_argument("--capture", choices=["auto", "window", "screen"], default="auto",
                    help="window：抓游戏窗口本身（不怕遮挡，需 FFmpeg 8+）；screen：抓屏幕区域；auto：能 window 就 window")
    ap.add_argument("--no-audio", action="store_true", help="不录声音")
    ap.add_argument("--play", help="让已在世界里的游戏立即开拍这个场景（如 sample）")
    args = ap.parse_args()

    save_dir = args.save_dir or (os.path.dirname(args.signal) if args.signal else None)
    if save_dir is None:
        dirs = find_save_dirs()
        if not dirs:
            print("找不到游戏存档目录（文档/Klei/DoNotStarveTogether/<账号>/client_save），请先启动一次游戏，或用 --save-dir 指定")
            return 2
        save_dir = dirs[0]
    ffmpeg = args.ffmpeg or find_ffmpeg()
    if ffmpeg is None:
        print("找不到 ffmpeg，请先安装（见 README），或用 --ffmpeg 指定")
        return 2

    code, msg = record(save_dir, args.out, ffmpeg, fps=args.fps, wait=args.wait, max_length=args.max_length,
                       capture=args.capture, audio=not args.no_audio, play=args.play)
    print(msg, flush=True)
    return code


if __name__ == "__main__":
    sys.exit(main())
