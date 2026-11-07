import std/unittest
import nimi/media/lyrics

suite "lyrics":
  test "multiple timestamps, fractions and offset stay ordered":
    let lines = parseLrc("[offset:-500]\n[00:02.50][00:04.5]你好\n[00:01]first\n[ar:artist]")
    check lines.len == 3
    check lines[0].time == 0.5
    check lines[1].time == 2.0
    check lines[2].time == 4.0
    check lines[2].text == "你好"
    check lines.activeLine(0) == -1
    check lines.activeLine(4) == 2
    check lines.activeLine(1) == 0

  test "malformed timestamps and non-finite values are ignored":
    check parseLrc("[00:nan]bad\n[00:61]bad\n[-1:02]bad\n[00:broken]bad").len == 0
