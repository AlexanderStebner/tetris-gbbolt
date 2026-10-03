"""Tetris's endings, played by the game's own code with its own sound: the rocket (type A,
100 000 points and more, three sizes), the dancers (type B won at level 9, one more
dancer per height) and the space shuttle (type B won at level 9, height 5)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _game  # noqa: E402

GROUP = 'animations'
FPS = 4194304 / 70224


def record(run, stop, longest):
    clip = _game.Clip(run)
    clip.start()
    for f in range(int(FPS * longest)):
        _game.frame(run)
        clip.add(run.screen())
        if stop(run.get('hGameState')):
            break
    last = len(clip.frames) - 1                    # an unchanging screen at the end: keep 2 s of it
    while last and clip.frames[last - 1] == clip.frames[-1]:
        last -= 1
    del clip.frames[last + int(FPS * 2):]
    return clip.finish()


def rocket(ctx, sprite):
    run = ctx.runner()
    _game.boot(run)
    run.record_sound()
    run.set('hGameType', _game.GAME_TYPE_A)
    run.set('hRocketSprite', sprite)
    run.set('hGameState', 0x2E)                    # State2E_RocketInit
    return record(run, lambda s: s == 0x10, 60)    # until State33_RocketEnd hands over


def type_b_win(ctx, height):
    """A type B game at level 9 and this height, set up by State0A_StartGame, at the moment
    its 25th line is cleared (what the line counter's code does then)."""
    run = ctx.runner()
    _game.boot(run)
    run.call('LoadGameTiles')
    run.set('hGameType', _game.GAME_TYPE_B)
    run.set('hTypeBLevel', 9)
    run.set('hTypeBHigh', height)
    run.set('hGameState', 0x0A)                    # State0A_StartGame
    _game.frame(run)
    for _ in range(3):
        _game.frame(run)
    run.record_sound()
    run.set('hTimer1', 100)                        # the game is won
    run.set('wMusicRequest', 2)
    run.set('hGameState', 0x22)                    # State22_DancersInit (level 9)
    return run


def build(ctx):
    out = []
    sizes = [(0x5A, 'small', '100 000 - 149 999 points'), (0x59, 'medium', '150 000 - 199 999 points'),
             (0x58, 'big', '200 000 points and more')]
    for sprite, size, when in sizes:
        clip = rocket(ctx, sprite)
        name = 'rocket-' + size
        out.append({
            'name': name, 'type': 'video', 'title': 'Rocket ending ({})'.format(size),
            'subtitle': 'type A, {} · {:.0f} s'.format(when, len(clip.frames) / FPS),
            'file': ctx.video(clip.frames, name, sound=clip),
            'poster': ctx.poster(clip.frames[min(len(clip.frames) - 1, int(FPS * 9))], name + '_poster'),
            'width': 160, 'height': 144, 'fps': FPS,
            'doc': ['After a type A game with {}: State0D_GameOverScreen picks the rocket by the score\'s '
                    'top digits (hRocketSprite $58-$5A: the higher the score, the bigger), then the '
                    'launch pad, smoke, ignition, lift-off and flight (states $2E-$33). Recorded by '
                    'running those game states frame by frame, with the game\'s own sound.'.format(when)],
            'users': ['State0D_GameOverScreen', 'State2E_RocketInit', 'State31_RocketLiftoff', 'State32_RocketFlight'],
        })
    for height in range(6):
        run = type_b_win(ctx, height)
        clip = record(run, lambda s: s in (0x05, 0x26), 90)
        dancers = 10 if height == 5 else height + 1
        name = 'dancers-{}'.format(height)
        out.append({
            'name': name, 'type': 'video', 'title': 'Dancers, height {}'.format(height),
            'subtitle': 'type B level 9 won · {} dancer{} · song {}'.format(dancers, 's' if dancers > 1 else '', 10 + height),
            'file': ctx.video(clip.frames, name, sound=clip),
            'poster': ctx.poster(clip.frames[min(len(clip.frames) - 1, int(FPS * 6))], name + '_poster'),
            'width': 160, 'height': 144, 'fps': FPS,
            'doc': ['Winning a type B game at level 9 brings out the dancers (State22_DancersInit): one '
                    'per height, all ten at height 5, each with its own speed (DancerAnimSpeeds), and a '
                    'song per height (10 + height). They dance until the song ends. The game here is set '
                    'up by State0A_StartGame (height {} garbage) and taken to the moment its 25th line '
                    'is cleared.'.format(height)],
            'users': ['State22_DancersInit', 'State23_Dancers', 'DancerAnimSpeeds'],
        })
        if height == 5:                            # height 5 goes on to the space shuttle
            clip = record(run, lambda s: s == 0x05, 60)
            out.append({
                'name': 'shuttle', 'type': 'video', 'title': 'Space shuttle ending',
                'subtitle': 'type B, level 9, height 5 · {:.0f} s'.format(len(clip.frames) / FPS),
                'file': ctx.video(clip.frames, 'shuttle', sound=clip),
                'poster': ctx.poster(clip.frames[min(len(clip.frames) - 1, int(FPS * 9))], 'shuttle_poster'),
                'width': 160, 'height': 144, 'fps': FPS,
                'doc': ['The best type B result, level 9 at height 5: after the dancers the space shuttle '
                        'launches (states $26-$2D), then the tally. Recorded by running those game states '
                        'frame by frame, with the game\'s own sound.'],
                'users': ['State26_ShuttleInit', 'State02_ShuttleLiftoff', 'State03_ShuttleFlight', 'State2D_ShuttleEnd'],
            })
    return out
