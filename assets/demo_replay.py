"""Tetris's two title demos, played by the game's own code with its own sound: the type A
demo at level 9, then the type B demo at level 9, height 2."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _game  # noqa: E402

GROUP = 'replays'
FPS = 4194304 / 70224


def build(ctx):
    run = ctx.runner()
    _game.boot(run)
    run.record_sound()
    run.set('hGameState', 0x06)                    # State06_TitleScreenInit
    clips = []
    for which in ('A', 'B'):
        for f in range(150):                       # the title screen, then the countdown runs out
            if f == 30:
                run.set('hTimer1', 0)
                run.set('hDemoCountdown', 1)
            _game.frame(run)
            if run.get('hGameState') not in (0x06, 0x07):
                break
        clip = _game.Clip(run)
        clip.start()
        held = []
        for f in range(int(FPS * 150)):
            clip.add(run.screen())
            held.append(run.get('hDemoButtons'))
            _game.frame(run)
            if run.get('hGameState') in (0x06, 0x07):
                break
        clips.append((which, clip.finish(), held))
    out = []
    for which, clip, held in clips:
        name = 'demo-type-' + which.lower()
        url = ctx.video(clip.frames, name, sound=clip)
        poster = ctx.poster(clip.frames[min(len(clip.frames) - 1, int(FPS * 8))], name + '_poster')
        what = ('a type A game at level 9' if which == 'A' else
                'a type B game at level 9 with height 2 (its garbage comes from DemoGarbage, not random)')
        out.append({
            'name': name, 'type': 'video', 'title': 'Type {} demo'.format(which),
            'subtitle': '{:.0f} s · the game\'s own code and sound'.format(len(clip.frames) / FPS),
            'file': url, 'poster': poster, 'width': 160, 'height': 144, 'fps': FPS,
            'lanes': _game.lanes(held),
            'doc': ['The title screen\'s demo of ' + what + ', recorded by running the game frame by '
                    'frame (RunGameState, UpdateSound, the VBlank handler, as MainLoop does) and drawing '
                    'what it leaves in VRAM and OAM; the sound is what its sound engine wrote. '
                    'DemoPlayback presses the recorded buttons and the pieces come from a fixed list, '
                    'so it plays out the same every time; it ends when the list runs out (DemoCheckEnd). '
                    'The two demos take turns (hDemo).',
                    'The lanes under the video are the buttons the demo holds.'],
            'users': ['StartDemo', 'DemoPlayback', 'DemoCheckEnd', 'SpawnNextPiece'],
        })
    return out
