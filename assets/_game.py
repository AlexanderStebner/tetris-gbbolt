"""Shared helpers for Tetris's asset plugins: the machine as SoftReset leaves it, and one
frame the way MainLoop and the VBlank interrupt run it."""

GAME_TYPE_A, GAME_TYPE_B = 0x37, 0x77


def boot(run):
    run.set(0xFF47, 0xE4)          # rBGP
    run.set(0xFF48, 0xE4)          # rOBP0
    run.set(0xFF49, 0xC4)          # rOBP1
    src = run.addr('OAMDMARoutine')
    run.copy_in('hOAMDMA', run.mem[src:src + 12])
    run.call('ClearBGMap0')
    run.call('InitSound')
    run.set('hGameType', GAME_TYPE_A)
    run.set('hMusicType', 0x1C)
    run.set(0xFF40, 0x80)


def frame(run):
    """MainLoop (without the joypad: demos press their own buttons) and the VBlank handler."""
    run.call('RunGameState')
    run.call('UpdateSound')
    for t in ('hTimer1', 'hTimer2'):
        if run.get(t):
            run.set(t, run.get(t) - 1)
    run.call('VBlankHandler')
    run.end_frame()


BUTTONS = [('A', 0x01), ('B', 0x02), ('Select', 0x04), ('Start', 0x08),
           ('Right', 0x10), ('Left', 0x20), ('Up', 0x40), ('Down', 0x80)]


def lanes(held_per_frame):
    out = []
    for name, bit in BUTTONS:
        spans, start = [], None
        for f, b in enumerate(held_per_frame + [0]):
            if b & bit and start is None:
                start = f
            elif not b & bit and start is not None:
                spans.append([start, f])
                start = None
        if spans:
            out.append({'name': name, 'spans': spans})
    return out


class Clip:
    """A stretch of a recording: frames and the sound written during them."""
    def __init__(self, run):
        self.run, self.f0, self.s0 = run, None, None
        self.frames, self.sound = [], []

    def start(self):
        self.s0 = len(self.run.sound)

    def add(self, screen):
        self.frames.append(screen)

    def finish(self):
        self.sound = self.run.sound[self.s0:self.s0 + len(self.frames)]
        return self
