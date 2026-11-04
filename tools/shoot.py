"""一条命令拍一段剧情：检查环境 → 启用模组 → 自动建片场世界 → 开拍 → 录制画面和声音 → 还原设置。

    python tools/shoot.py --check          只检查环境，告诉你还缺什么
    python tools/shoot.py sample           拍 scripts/storydirector/scenes/sample.lua
    python tools/shoot.py meeting --out 成片.mp4

游戏没开时：临时在 mods/modsettings.lua 启用本模组，启动游戏，自动新建「剧情片场」世界并开拍，
拍完把 modsettings.lua 改回原样。拍完游戏不会关，改完剧本再运行同一条命令就在当前世界里重拍。
游戏已开着时：直接让游戏开拍（需要是由本脚本启动、已进入片场世界的游戏）。
"""

import argparse
import datetime
import os
import re
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import record  # noqa: E402

MOD_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MOD_NAME = os.path.basename(MOD_ROOT)
MODS_DIR = os.path.dirname(MOD_ROOT)
GAME_DIR = os.path.dirname(MODS_DIR)
MODSETTINGS = os.path.join(MODS_DIR, "modsettings.lua")
SCENES_DIR = os.path.join(MOD_ROOT, "scripts", "storydirector", "scenes")
AUTOHOST_FILE = "story_director_autohost"
STEAM_APP_URL = "steam://rungameid/322330"
GAME_PROCESSES = ("dontstarve_steam_x64.exe", "dontstarve_steam.exe", "dontstarve_rail_x64.exe", "dontstarve_rail.exe")
ENABLE_MARK = "-- story_director: shoot.py 临时启用，拍完自动删除"

OK, BAD, WARN = "[ OK ]", "[缺少]", "[注意]"


# ---------------------------------------------------------------------------
# 环境检查

def check_environment(scene, audio, quiet=False):
    """返回 (是否可以开拍, 信息字典)。"""
    info = {}
    problems = 0

    def line(tag, text, hint=None):
        if not quiet or tag != OK:
            print(f"{tag} {text}")
            if hint:
                print("       " + hint)

    if sys.platform != "win32":
        line(BAD, "只支持 Windows")
        return False, info

    if sys.version_info < (3, 8):
        line(BAD, f"Python {sys.version.split()[0]}，需要 3.8 以上", "到 https://www.python.org/downloads/ 安装新版")
        problems += 1
    else:
        line(OK, f"Python {sys.version.split()[0]}")

    if os.path.basename(MODS_DIR).lower() != "mods" or not os.path.isfile(MODSETTINGS):
        line(BAD, f"模组目录不对：{MOD_ROOT}",
             "要把本项目放在游戏目录的 mods 文件夹里，如 ...\\Don't Starve Together\\mods\\story_director")
        problems += 1
    else:
        line(OK, f"模组目录：{MOD_ROOT}")
        info["steam"] = os.path.isfile(os.path.join(GAME_DIR, "bin64", "dontstarve_steam_x64.exe")) or \
            os.path.isfile(os.path.join(GAME_DIR, "bin", "dontstarve_steam.exe"))
        if not info["steam"]:
            line(WARN, "不是 Steam 版游戏，脚本没法自动启动游戏", "到时按提示手动启动游戏即可")

    if scene is not None:
        if not re.fullmatch(r"[A-Za-z0-9_]+", scene):
            line(BAD, f"场景名只能用字母、数字和下划线：{scene}")
            problems += 1
        elif not os.path.isfile(os.path.join(SCENES_DIR, scene + ".lua")):
            names = sorted(f[:-4] for f in os.listdir(SCENES_DIR) if f.endswith(".lua"))
            line(BAD, f"找不到场景文件 scenes/{scene}.lua", "现有场景：" + "、".join(names))
            problems += 1
        else:
            line(OK, f"场景：scenes/{scene}.lua")

    dirs = record.find_save_dirs()
    if info.get("steam"):
        # Steam 版不会用 WeGame 版（DoNotStarveTogetherRail）的存档目录
        dirs = [d for d in dirs if "DoNotStarveTogetherRail" not in d] or dirs
    if not dirs:
        line(BAD, "找不到游戏存档目录（文档\\Klei\\DoNotStarveTogether\\<账号>\\client_save）",
             "先正常启动一次游戏、进到主菜单再退出，或用 --save-dir 指定")
        problems += 1
    else:
        info["save_dir"] = dirs[0]
        line(OK, f"存档目录：{dirs[0]}")
        if len(dirs) > 1:
            line(WARN, f"找到 {len(dirs)} 个账号的存档目录，用的是最近用过的那个", "不对的话用 --save-dir 指定")

    ffmpeg = record.find_ffmpeg()
    if ffmpeg is None:
        line(BAD, "找不到 ffmpeg", "在 PowerShell 里运行：winget install Gyan.FFmpeg ，装完重新打开命令行窗口")
        problems += 1
    else:
        info["ffmpeg"] = ffmpeg
        info["gfxcapture"] = record.has_gfxcapture(ffmpeg)
        version = record.ffmpeg_version(ffmpeg)
        if info["gfxcapture"]:
            line(OK, f"ffmpeg {version}（支持窗口捕获，游戏窗口被挡住也能录）")
        else:
            line(WARN, f"ffmpeg {version} 不支持窗口捕获，会改为录屏幕区域，录制时不要遮挡游戏窗口",
                 "想用窗口捕获：winget upgrade Gyan.FFmpeg（需要 FFmpeg 8 以上，Windows 10 1903 以上）")

    if audio:
        try:
            import numpy  # noqa: F401
            import soundcard
            speaker = soundcard.default_speaker()
            line(OK, f"录音设备：{speaker.name}（会录进电脑上此时所有声音）")
        except ImportError:
            line(BAD, "缺少录音用的 Python 库", "运行：python -m pip install -r requirements.txt")
            problems += 1
        except Exception as e:  # 没有声卡、驱动异常等
            line(BAD, f"打不开默认扬声器录音：{e}", "检查系统声音输出设备，或加 --no-audio 只录画面")
            problems += 1

    return problems == 0, info


# ---------------------------------------------------------------------------
# 游戏与模组设置

def game_running():
    out = subprocess.run(["tasklist", "/FO", "CSV", "/NH"], capture_output=True, text=True, errors="replace")
    names = {row.split(",")[0].strip('"').lower() for row in out.stdout.splitlines() if row}
    return any(p in names for p in GAME_PROCESSES)


def read_text(path):
    # newline="" 保留文件原本的换行符，还原时不改动其他行
    with open(path, "r", encoding="utf-8", errors="surrogateescape", newline="") as f:
        return f.read()


def mod_force_enabled(text):
    pattern = r'^\s*ForceEnableMod\(\s*["\']' + re.escape(MOD_NAME) + r'["\']\s*\)'
    return re.search(pattern, text, re.M) is not None


def enable_mod():
    """在 modsettings.lua 末尾加一行 ForceEnableMod。已经启用则不动。返回是否改了文件。"""
    text = read_text(MODSETTINGS)
    if mod_force_enabled(text):
        return False
    nl = "\r\n" if "\r\n" in text else "\n"
    with open(MODSETTINGS, "a", encoding="utf-8", newline="") as f:
        f.write(f'{nl}{ENABLE_MARK}{nl}ForceEnableMod("{MOD_NAME}"){nl}')
    return True


def disable_mod():
    """只删掉 enable_mod 加的那两行，文件里其他内容保持原样。"""
    text = read_text(MODSETTINGS)
    new = re.sub(r'(\r?\n)?' + re.escape(ENABLE_MARK) + r'\r?\nForceEnableMod\("[^"]*"\)(\r?\n)?', "", text)
    if new != text:
        with open(MODSETTINGS, "w", encoding="utf-8", errors="surrogateescape", newline="") as f:
            f.write(new)


def write_flag(save_dir, content):
    with open(os.path.join(save_dir, AUTOHOST_FILE), "w", encoding="utf-8") as f:
        f.write(content)


def remove_flag(save_dir):
    try:
        os.remove(os.path.join(save_dir, AUTOHOST_FILE))
    except OSError:
        pass


# ---------------------------------------------------------------------------

def main():
    sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser(description="一条命令拍一段剧情并录成带声音的视频")
    ap.add_argument("scene", nargs="?", help="场景名，对应 scripts/storydirector/scenes/<场景名>.lua")
    ap.add_argument("--check", action="store_true", help="只检查环境")
    ap.add_argument("--out", help="输出 mp4（默认 takes/<场景名>_<时间>.mp4）")
    ap.add_argument("--save-dir", help="client_save 目录（默认自动查找）")
    ap.add_argument("--ffmpeg", help="ffmpeg.exe 路径（默认自动查找）")
    ap.add_argument("--capture", choices=["auto", "window", "screen"], default="auto",
                    help="auto（默认）：能抓窗口就抓窗口，否则录屏幕区域")
    ap.add_argument("--no-audio", action="store_true", help="只录画面")
    ap.add_argument("--fps", type=int, default=30)
    ap.add_argument("--max-length", type=float, default=600, help="单条最长秒数")
    args = ap.parse_args()

    if args.scene is None and not args.check:
        ap.print_help()
        return 2

    print("== 环境检查 ==")
    ok, info = check_environment(args.scene, audio=not args.no_audio)
    if args.save_dir:
        info["save_dir"] = args.save_dir
    if args.ffmpeg:
        info["ffmpeg"] = args.ffmpeg
    if args.check:
        print("环境齐了，可以开拍：python tools/shoot.py sample" if ok else "请按上面的提示补齐后再试")
        return 0 if ok else 1
    if not ok or "save_dir" not in info or "ffmpeg" not in info:
        print("环境不完整，没有开拍。按上面的提示补齐后再运行。")
        return 1

    save_dir = info["save_dir"]
    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    out = args.out or os.path.join(MOD_ROOT, "takes", f"{args.scene}_{stamp}.mp4")
    common = dict(fps=args.fps, max_length=args.max_length, capture=args.capture, audio=not args.no_audio)

    print("\n== 开拍 ==")
    if game_running():
        print("游戏已在运行，直接在当前世界开拍。")
        code, msg = record.record(
            save_dir, out, info["ffmpeg"], wait=20, play=args.scene,
            start_timeout_hint="游戏没有响应。确认游戏已进入由本脚本建的「剧情片场」世界；"
                               "如果游戏是自己手动打开的，请关闭游戏后重新运行本命令。",
            **common)
        print(msg)
        return code

    changed = enable_mod()
    if changed:
        print(f"已在 {MODSETTINGS} 临时启用模组 {MOD_NAME}（拍完自动删除）")
    write_flag(save_dir, "HOST " + args.scene)
    try:
        if info.get("steam"):
            print("正在通过 Steam 启动游戏……")
            os.startfile(STEAM_APP_URL)
        else:
            print("请现在手动启动《饥荒联机版》。")
        print("游戏会自动新建一个离线的「剧情片场」世界（存档位里会多一个 Story Director 存档），选好角色后开拍。")
        print("如果游戏弹出公告或提示框，点掉即可；第一次建世界大约需要 1～2 分钟。")
        code, msg = record.record(
            save_dir, out, info["ffmpeg"], wait=600,
            start_timeout_hint="10 分钟内没有开拍。看看游戏是不是停在某个界面上（弹窗、登录、更新），"
                               "处理后重新运行；也可以查看 文档\\Klei\\DoNotStarveTogether\\client_log.txt 里的 [STORY_DIRECTOR] 行。",
            **common)
        print(msg)
        if code in (0, 1):
            print("游戏没有关闭：改完剧本后再运行同一条命令，就在这个世界里重拍。")
        return code
    except KeyboardInterrupt:
        print("已中断。")
        return 130
    finally:
        remove_flag(save_dir)
        if changed:
            # 游戏启动时已读过 modsettings.lua，删掉这行不影响本次运行中的重拍
            time.sleep(0.5)
            disable_mod()
            print("已还原 modsettings.lua")


if __name__ == "__main__":
    sys.exit(main())
