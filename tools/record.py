"""等待剧情导演模组的 START/STOP 信号，用 ffmpeg 录制《饥荒联机版》窗口画面和系统声音。

用法：
    python record.py --signal <client_save 目录>/story_director_signal --out take.mp4 [--ffmpeg ffmpeg.exe] [--play sample]

模组在 client_save 下写 "START <场景名> <时间戳>" / "STOP ..."。脚本只响应启动后新写入的信号。
加 --play 时先写 client_save/story_director_cmd，让已进入世界的游戏立即开拍（不加则等进世界后的自动开拍）。
默认用 Windows 图形捕获（ffmpeg gfxcapture）直接抓游戏窗口，游戏窗口被挡住也不影响；
--capture screen 改为录桌面区域（gdigrab），录制期间不能被遮挡。
声音用 soundcard 录默认扬声器的回环（会录进此时电脑上所有声音），--no-audio 关闭。
画面和声音分开录，停止时同一刻结束，按两者的结束时刻对齐后合成。
"""

import argparse
import ctypes
import os
import re
import subprocess
import sys
import threading
import time
import wave

import win32gui

WINDOW_TITLE = "Don't Starve Together"
SAMPLE_RATE = 48000


def read_signal(path):
    """返回去掉 SetPersistentString 文件头（"KLEI     1"）后的信号文本。"""
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            text = f.read()
    except OSError:
        return ""
    m = re.search(r"(START|STOP)\b.*", text)
    return m.group(0).strip() if m else ""


def send_command(path, command):
    """写入模组轮询的指令文件，让游戏开拍。"""
    with open(path, "w", encoding="utf-8") as f:
        f.write(f"{command} {time.time():.0f}")


def game_window():
    hwnd = win32gui.FindWindow(None, WINDOW_TITLE)
    if not hwnd:
        raise RuntimeError("找不到游戏窗口：" + WINDOW_TITLE)
    return hwnd


def game_client_rect(hwnd):
    left, top, right, bottom = win32gui.GetClientRect(hwnd)
    x, y = win32gui.ClientToScreen(hwnd, (left, top))
    # yuv420p 要求宽高为偶数
    w = (right - left) // 2 * 2
    h = (bottom - top) // 2 * 2
    return x, y, w, h


def wait_for(path, prefix, baseline, deadline):
    while time.time() < deadline:
        text = read_signal(path)
        if text != baseline and text.startswith(prefix):
            return text
        time.sleep(0.05)
    return None


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


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser()
    ap.add_argument("--signal", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--ffmpeg", default="ffmpeg")
    ap.add_argument("--fps", type=int, default=30)
    ap.add_argument("--wait", type=float, default=900, help="等待 START 的最长秒数")
    ap.add_argument("--max-length", type=float, default=180, help="单条录像最长秒数")
    ap.add_argument("--capture", choices=["window", "screen"], default="window",
                    help="window：抓游戏窗口本身（默认，不怕遮挡）；screen：抓屏幕区域")
    ap.add_argument("--no-audio", action="store_true", help="不录声音")
    ap.add_argument("--play", help="让已在世界里的游戏立即开拍这个场景（如 sample）")
    args = ap.parse_args()

    # 按物理像素取窗口坐标，和 gdigrab 的坐标系一致
    ctypes.windll.shcore.SetProcessDpiAwareness(2)

    baseline = read_signal(args.signal)
    if args.play:
        # 指令文件与信号文件同在 client_save 目录
        send_command(os.path.join(os.path.dirname(args.signal), "story_director_cmd"), "PLAY " + args.play)
        print("已发送开拍指令：", args.play, flush=True)
    print("等待 START 信号：", args.signal, flush=True)
    start = wait_for(args.signal, "START", baseline, time.time() + args.wait)
    if start is None:
        print("超时：没有收到 START", flush=True)
        return 2

    hwnd = game_window()
    x, y, w, h = game_client_rect(hwnd)
    out = os.path.abspath(args.out)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    base, _ = os.path.splitext(out)
    video_path = out if args.no_audio else base + ".video.mp4"
    audio_path = base + ".audio.wav"

    if args.capture == "window":
        # Windows 图形捕获：直接抓游戏窗口内容，不受其他窗口遮挡
        print(f"收到 {start}，窗口捕获 hwnd={hwnd} {w}x{h}", flush=True)
        source = [
            "-filter_complex",
            f"gfxcapture=hwnd={hwnd}:capture_cursor=0:max_framerate={args.fps},"
            f"hwdownload,format=bgra,fps={args.fps},crop=trunc(iw/2)*2:trunc(ih/2)*2",
        ]
    else:
        # 屏幕区域捕获：录桌面上游戏窗口所在的区域，期间不能被遮挡
        print(f"收到 {start}，屏幕区域 {w}x{h} @ ({x},{y})", flush=True)
        source = [
            "-f", "gdigrab", "-framerate", str(args.fps), "-draw_mouse", "0",
            "-offset_x", str(x), "-offset_y", str(y), "-video_size", f"{w}x{h}",
            "-i", "desktop",
        ]

    audio = None
    if not args.no_audio:
        audio = LoopbackRecorder()
        audio.start()

    cmd = [
        args.ffmpeg, "-hide_banner", "-loglevel", "warning", "-y",
        *source,
        "-c:v", "libx264", "-preset", "veryfast", "-crf", "18", "-pix_fmt", "yuv420p",
        "-movflags", "+faststart",
        video_path,
    ]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)

    stop = wait_for(args.signal, "STOP", start, time.time() + args.max_length)
    print("收到", stop or "超时，强制停止", flush=True)
    # 画面和声音在同一刻停止，之后用各自时长反推起点
    video_end = time.perf_counter()
    proc.stdin.write(b"q")
    proc.stdin.flush()
    if audio is not None:
        audio.stop()
    try:
        proc.wait(timeout=30)
    except subprocess.TimeoutExpired:
        proc.kill()

    if audio is not None:
        audio_len = audio.save_wav(audio_path)
        video_len = probe_duration(args.ffmpeg, video_path)
        # 声音比画面早开始多少秒（正数则裁掉声音开头，负数则在声音前补静音）
        lead = (video_end - video_len) - (audio.end_time - audio_len)
        print(f"画面 {video_len:.2f}s，声音 {audio_len:.2f}s，声音提前 {lead:+.3f}s", flush=True)
        if lead >= 0:
            audio_in = ["-ss", f"{lead:.3f}", "-i", audio_path]
            afilter = []
        else:
            audio_in = ["-i", audio_path]
            afilter = ["-af", f"adelay={int(-lead * 1000)}:all=1"]
        subprocess.run([
            args.ffmpeg, "-hide_banner", "-loglevel", "warning", "-y",
            "-i", video_path, *audio_in,
            "-map", "0:v", "-map", "1:a", *afilter,
            "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-shortest",
            "-movflags", "+faststart", out,
        ], check=True)
        os.remove(video_path)
    print("已保存：", out, flush=True)
    return 0 if stop else 1


if __name__ == "__main__":
    sys.exit(main())
