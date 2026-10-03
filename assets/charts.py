"""Numbers behind Tetris, read from its tables and worked out from its own routines."""
import random

GROUP = 'charts'
FPS = 4194304 / 70224
NAMES = ['L', 'J', 'I', 'O', 'Z', 'S', 'T']        # piece types $00, $04 ... $18


def fall_chart(ctx):
    table = ctx.addr('FallDelayTable')
    normal = [[lv, ctx.rom[table + lv]] for lv in range(21)]
    hard = [[lv, ctx.rom[table + min(lv + 10, 20)]] for lv in range(21)]
    return {
        'name': 'chart-fall-speed', 'type': 'chart', 'kind': 'step', 'title': 'Fall speed',
        'subtitle': 'frames per row, by level',
        'x': 'level', 'y': 'frames per row',
        'series': [{'name': 'normal', 'points': normal}, {'name': 'hard mode (Down + Start)', 'points': hard}],
        'doc': ['How long a piece waits before it falls a row (FallDelayTable, read by SetFallSpeed): '
                '52 frames at level 0, about one row a second, down to 2 frames at level 20, 30 rows a '
                'second. Hard mode (hold Down when pressing Start) plays 10 levels faster, but never '
                'faster than level 20. The levels go up every 10 lines in type A.'],
        'users': ['SetFallSpeed', 'FallDelayTable'],
    }


def points_chart(ctx):
    series = []
    for name, base in (('single', 40), ('double', 100), ('triple', 300), ('tetris', 1200)):
        series.append({'name': name, 'points': [[lv, base * (lv + 1)] for lv in range(21)]})
    return {
        'name': 'chart-line-points', 'type': 'chart', 'kind': 'line', 'title': 'Points per line clear',
        'subtitle': '40 / 100 / 300 / 1200 x (level + 1)',
        'x': 'level', 'y': 'points',
        'series': series,
        'doc': ['What a clear is worth in type A (AwardLineClearPoints): the game counts the clears '
                'in wScoreTally and adds 40, 100, 300 or 1200 points (BCD) level + 1 times. A tetris '
                'is worth 30 singles, so it pays to stack up and wait for the long I piece. '
                'Soft drops are counted too and added at the end of the game (TallyDropPoints). A type A score of 100 000 earns the rocket '
                'ending, and it grows at 150 000 and 200 000.'],
        'users': ['AwardLineClearPoints', 'AddScoreBCD'],
    }


def roll(div):
    """SpawnNextPiece's count: rDIV - 1 steps through the 7 types; with the loop's cycles."""
    steps = (div - 1) & 0xFF
    return (steps % 7) * 4, 8 + 56 * steps - 4 * (steps // 7) + 16 + 72


def deal(rng, count):
    """Pieces as SpawnNextPiece deals them outside demos and 2-player games. DIV counts up
    every 256 cycles: the second and third tries read it after the first count's cycles,
    so they are not independent of it. The time between two pieces is taken as random."""
    current, preview, seq = 0, 0, []
    for _ in range(count):
        clock = rng.randrange(0x10000)             # the divider's 16-bit counter
        for attempt in range(3):
            r, cycles = roll(clock >> 8)
            clock += cycles
            if attempt == 2 or (preview | r | current) & 0xFC != current:
                break
        current, preview = preview, r          # the old preview falls, the new roll is previewed later
        seq.append(current >> 2)
    return seq


def piece_images(ctx):
    import site_gen
    sprites = site_gen.render_sprites(ctx.project, 28)
    run = ctx.runner()
    run.call('LoadGameTiles')
    out = []
    for p in range(7):
        entries = sprites[4 * p]
        img = [[255] * 32 for _ in range(16)]
        if entries:
            x0, y0 = min(e[1] for e in entries), min(e[0] for e in entries)
            for y, x, t, attr in entries:
                for r in range(8):
                    lo, hi = run.mem[0x8000 + t * 16 + 2 * r], run.mem[0x8001 + t * 16 + 2 * r]
                    for cx in range(8):
                        bit = cx if attr & 0x20 else 7 - cx
                        v = ((hi >> bit) & 1) << 1 | ((lo >> bit) & 1)
                        px, py = x - x0 + cx, y - y0 + r
                        if v and 0 <= px < 32 and 0 <= py < 16:
                            img[py][px] = v
        out.append({'image': {'width': 32, 'height': 16, 'pixels': ctx.pixels(img)}})
    return out


def randomizer(ctx):
    n = 200000
    seq = deal(random.Random(1989), n)
    count = [0] * 7
    after = [[0] * 7 for _ in range(7)]
    for a, b in zip(seq, seq[1:]):
        after[a][b] += 1
    for p in seq:
        count[p] += 1
    first = [0] * 7
    for div in range(256):
        first[roll(div)[0] >> 2] += 1
    imgs = piece_images(ctx)
    rows = []
    for p in range(7):
        rows.append([imgs[p], NAMES[p], '${:02X}'.format(4 * p),
                     '{:.1f} %'.format(100 * first[p] / 256),
                     '{:.1f} %'.format(100 * count[p] / n),
                     '{:.1f} %'.format(100 * after[p][p] / sum(after[p]))])
    repeat = sum(after[p][p] for p in range(7)) / (n - 1)
    return {
        'name': 'table-piece-odds', 'type': 'table', 'title': 'Piece odds',
        'subtitle': 'the randomizer, worked out ({:.1f} % repeats instead of 14.3 %)'.format(100 * repeat),
        'columns': ['piece', 'name', 'id', 'one roll', 'dealt', 'same piece next'],
        'rows': rows,
        'doc': ['SpawnNextPiece counts rDIV - 1 steps through the 7 piece types and takes where it '
                'stops, so for one roll (column "one roll", all 256 DIV values) L, J, I and O are a '
                'little more likely: 256 is not a multiple of 7.',
                'It rolls up to three times: a new roll is kept when (previous roll | new roll | '
                'piece now falling) & $FC differs from the falling piece. That is meant to stop '
                'repeats, but the OR also rerolls other pieces whose bits are all inside the falling '
                'one (with a T falling, $18, an L $00, I $08 or Z $10 can be rerolled too). The third roll is kept '
                'whatever it is, and the result shows up only one piece later (the preview is the '
                'previous roll).',
                'The counting loop takes 56 cycles a step and DIV counts up every 256 cycles, so the '
                'second and third tries read a DIV that follows from the first. Column "dealt" comes '
                'from {} pieces dealt this way, with a random time between pieces; "same piece next" '
                'is how often that piece comes twice in a row (1 in 7 = 14.3 % for a fair die). '
                'The upshot: L ($00, whose bits are inside every other piece) comes least, O and T '
                'most, and repeats are rarer than with a fair die but still happen. '
                'Demos and 2-player games deal from a fixed list instead (wPieceList).'.format(n)],
        'users': ['SpawnNextPiece'],
    }


def dancer_table(ctx):
    table = ctx.addr('DancerAnimSpeeds')
    rows = []
    for i in range(10):
        f = ctx.rom[table + i]
        rows.append([i + 1, f, '{:.2f}'.format(FPS / f)])
    return {
        'name': 'table-dancer-speeds', 'type': 'table', 'title': 'Dancer speeds',
        'subtitle': 'frames per dance step, per dancer',
        'columns': ['dancer', 'frames per step', 'steps per second'],
        'rows': rows,
        'doc': ['Each of the 10 dancers of the type B ending steps at its own pace '
                '(DancerAnimSpeeds), so they never dance in sync. Height h brings out h + 1 '
                'of them, height 5 all ten.'],
        'users': ['State23_Dancers', 'DancerAnimSpeeds'],
    }


def build(ctx):
    return [fall_chart(ctx), points_chart(ctx), randomizer(ctx), dancer_table(ctx)]
