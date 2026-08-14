#!/usr/bin/env python3
"""에뮬레이터 UI 자동화 헬퍼 — uiautomator dump 파싱 + 탭/입력.

사용법:
  emu_ui.py dump [file.xml]        # UI 계층을 파일로 저장
  emu_ui.py tap <text>             # text를 포함한 노드 중심 탭
  emu_ui.py tapdesc <desc>         # content-desc를 포함한 노드 중심 탭
  emu_ui.py type <text>            # ASCII 텍스트 입력 (한글 불가)
  emu_ui.py key <keycode>          # 키 이벤트 (예: KEYCODE_DEL)
  emu_ui.py text <text>            # dump에서 text를 포함한 노드의 text 값
"""
import re
import subprocess
import sys

ADB = r'C:\Users\mathe\Android\platform-tools\adb.exe'


def sh(cmd, timeout=60):
    r = subprocess.run(['cmd.exe', '/c', cmd],
                       capture_output=True, text=True, timeout=timeout)
    return r.stdout


def dump():
    sh(f'{ADB} shell uiautomator dump /sdcard/ui.xml > NUL 2>&1')
    return sh(f'{ADB} shell cat /sdcard/ui.xml')


def find_nodes(xml, text=None, desc=None):
    out = []
    # 속성 순서: ... text=".." resource-id class package content-desc ... bounds="[x1,y1][x2,y2]"
    for m in re.finditer(
            r'<node[^>]*?text="([^"]*)"[^>]*?content-desc="([^"]*)"[^>]*?'
            r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', xml):
        t, d, x1, y1, x2, y2 = m.groups()
        if (text and text in t) or (desc and d and desc in d):
            out.append(((int(x1) + int(x2)) // 2, (int(y1) + int(y2)) // 2,
                        t, d))
    return out


def main():
    cmd = sys.argv[1]
    if cmd == 'dump':
        xml = dump()
        path = sys.argv[2] if len(sys.argv) > 2 else '/tmp/ui.xml'
        with open(path, 'w', encoding='utf-8') as f:
            f.write(xml)
        print(f'saved {len(xml)} bytes -> {path}')
    elif cmd == 'tap' or cmd == 'tapdesc':
        target = sys.argv[2]
        xml = dump()
        nodes = find_nodes(xml, text=target if cmd == 'tap' else None,
                           desc=target if cmd == 'tapdesc' else None)
        if not nodes:
            print(f'NOT FOUND: {target}')
            sys.exit(1)
        x, y, t, d = nodes[0]
        print(f'tap ({x},{y}) text={t!r} desc={d!r}')
        sh(f'{ADB} shell input tap {x} {y}')
    elif cmd == 'type':
        sh(f'{ADB} shell input text "{sys.argv[2]}"')
        print('typed')
    elif cmd == 'key':
        sh(f'{ADB} shell input keyevent {sys.argv[2]}')
        print('key sent')
    elif cmd == 'text':
        target = sys.argv[2]
        xml = dump()
        for x, y, t, d in find_nodes(xml, text=target):
            print(repr(t))
    else:
        print(__doc__)
        sys.exit(1)


if __name__ == '__main__':
    main()
