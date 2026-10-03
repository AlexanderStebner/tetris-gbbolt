; Disassembly of "tetris.gb"
; This file was created with:
; mgbdis v3.0 - Game Boy ROM disassembler by Matt Currie and contributors.
; https://github.com/mattcurrie/mgbdis

SECTION "ROM Bank $000", ROM0[$0]

;@ def RST_00()
;@ path: boot/vectors
;@ Restart vector $00 (unused): restarts the game.
;@ test: skip never returns
;@ sig: 1b6354c2
RST_00::
;> goto(Start)
	jp Start


	db $00, $00, $00, $00, $00

;@ def RST_08()
;@ path: boot/vectors
;@ Restart vector $08 (unused): restarts the game.
;@ test: skip never returns
;@ sig: ec08f8fe
RST_08::
;> goto(Start)
	jp Start


	db $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff
	db $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff

;@ def JumpTable(index: a)
;@ path: boot/vectors
;@ Jump-table dispatch, used as `rst $28`.
;@ The `rst $28` is directly followed by a table of 16-bit addresses. Instead
;@ of returning, execution continues at entry `index` of that table.
;@ clobbers: a, de, hl
;@ test: skip rewrites the return address on the stack
;@ sig: 64d914ee
JumpTable::
;> offset = 2 * index
	add a
;> table = pop_return_address()       # the table starts right after `rst $28`
	pop hl
;> target = mem16[table + offset]
	ld e, a
	ld d, $00
	add hl, de
	ld e, [hl]
	inc hl
	ld d, [hl]
;> goto(target)
	push de
	pop hl
	jp hl


	db $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff

;@ def VBlankInterrupt()
;@ path: boot/vectors
;@ Interrupt vector $40.
;@ test: skip interrupt vector
;@ sig: f2df0001
VBlankInterrupt::
;> goto(VBlankHandler)
	jp VBlankHandler


	db $ff, $ff, $ff, $ff, $ff

;@ def LCDCInterrupt()
;@ path: boot/vectors
;@ Interrupt vector $48. Never enabled; points at a bare `reti`.
;@ test: skip interrupt vector
;@ sig: 246baa04
LCDCInterrupt::
;> goto(TimerHandler)
	jp TimerHandler


	db $ff, $ff, $ff, $ff, $ff

;@ def TimerOverflowInterrupt()
;@ path: boot/vectors
;@ Interrupt vector $50. Never enabled; points at a bare `reti`.
;@ test: skip interrupt vector
;@ sig: 246baa04
TimerOverflowInterrupt::
;> goto(TimerHandler)
	jp TimerHandler


	db $ff, $ff, $ff, $ff, $ff

;@ def SerialTransferCompleteInterrupt()
;@ path: boot/vectors
;@ Interrupt vector $58.
;@ test: skip interrupt vector
;@ sig: 35e77594
SerialTransferCompleteInterrupt::
;> goto(SerialHandler)
	jp SerialHandler


;@ def SerialHandler()
;@ path: system/link
;@ Serial interrupt: a byte has been sent/received over the link cable.
;@ Runs the link state machine and flags the transfer as done.
;@ writes: hSerialDone
;@ test: skip interrupt handler (ends in reti)
;@ sig: e86c3ac8
SerialHandler::
;> # (all registers are saved and restored)
	push af
	push hl
	push de
	push bc
;> RunSerialState()
	call RunSerialState
;> hSerialDone = 1
	ld a, $01
	ldh [hSerialDone], a
;> return                                 # registers restored, reti
	pop bc
	pop de
	pop hl
	pop af
	reti


;@ def RunSerialState()
;@ path: system/link
;@ Calls the handler for the current link-cable state.
;@ reads: hSerialState
;@ test: hSerialState = rand(0, 4)
;@ sig: 0464fc28
RunSerialState::
;> SerialStateTable[hSerialState]()
	ldh a, [hSerialState]
	rst $28

SerialStateTable::
	dw SerialHandshake
	dw SerialReceive
	dw SerialExchange
	dw SerialExchangeDelayed
	dw DoNothing

;@ def SerialHandshake()
;@ path: system/link
;@ Serial state 0: who is master? On the title screen, a received $55 means
;@ the other Game Boy is waiting, so we become master; a received $29 means
;@ it called us, so we become slave. In any other state the game goes back
;@ to the title screen.
;@ reads: hGameState, rSB
;@ writes: hGameState, hSerialRole, rSC
;@ test: hGameState = rng.choice([0x07, 0x07, 0x06, 0x00])
;@ test: rSB = rng.choice([0x55, 0x29, 0x00])
;@ sig: 7503ce1b
SerialHandshake::
;> if hGameState != 0x07:
	ldh a, [hGameState]
	cp $07
	jr z, .titleScreen

;>     if hGameState == 0x06:
	cp $06
;>         return
	ret z

;>     hGameState = 0x06
	ld a, $06
	ldh [hGameState], a
;>     return
	ret

;> if rSB == SERIAL_SLAVE:
.titleScreen
	ldh a, [rSB]
	cp SERIAL_SLAVE
	jr nz, .notSlave

;>     hSerialRole = SERIAL_MASTER
	ld a, SERIAL_MASTER
	ldh [hSerialRole], a
;>     rSC = 0x01
	ld a, $01
;=@else
	jr .setSC

;> elif rSB != SERIAL_MASTER:
.notSlave
	cp SERIAL_MASTER
;>     return
	ret nz

;>@else else:
;>     hSerialRole = SERIAL_SLAVE
	ld a, SERIAL_SLAVE
	ldh [hSerialRole], a
;>     rSC = 0x00
	xor a

.setSC
	ldh [rSC], a
;> return
	ret


;@ def SerialReceive()
;@ path: system/link
;@ Serial state 1: just keeps the received byte.
;@ writes: hSerialRx
;@ sig: fcc8af8e
SerialReceive::
;> hSerialRx = rSB
	ldh a, [rSB]
	ldh [hSerialRx], a
	ret


;@ def SerialExchange()
;@ path: system/link
;@ Serial state 2: keeps the received byte; the slave immediately prepares
;@ its next byte (hSerialTx, then $FF) and waits for the master's clock.
;@ reads: hSerialRole, hSerialTx
;@ writes: hSerialRx, rSB, hSerialTx, rSC
;@ test: hSerialRole = rng.choice([SERIAL_MASTER, SERIAL_SLAVE])
;@ sig: d333c1bb
SerialExchange::
;> hSerialRx = rSB
	ldh a, [rSB]
	ldh [hSerialRx], a
;> if hSerialRole == SERIAL_MASTER:
	ldh a, [hSerialRole]
	cp SERIAL_MASTER
;>     return
	ret z

;> rSB = hSerialTx
	ldh a, [hSerialTx]
	ldh [rSB], a
;> hSerialTx = 0xFF
	ld a, $ff
	ldh [hSerialTx], a
;> rSC = 0x80
	ld a, $80
	ldh [rSC], a
;> return
	ret


;@ def SerialExchangeDelayed()
;@ path: system/link
;@ Serial state 3: like SerialExchange, but the slave waits a moment (with
;@ interrupts on) before it is ready, and does not reset hSerialTx.
;@ reads: hSerialRole, hSerialTx
;@ writes: hSerialRx, rSB, rSC
;@ test: hSerialRole = rng.choice([SERIAL_MASTER, SERIAL_SLAVE])
;@ sig: 6de968e2
SerialExchangeDelayed::
;> hSerialRx = rSB
	ldh a, [rSB]
	ldh [hSerialRx], a
;> if hSerialRole == SERIAL_MASTER:
	ldh a, [hSerialRole]
	cp SERIAL_MASTER
;>     return
	ret z

;> rSB = hSerialTx
	ldh a, [hSerialTx]
	ldh [rSB], a
;> enable_interrupts()
	ei
;> Delay()
	call Delay
;> rSC = 0x80
	ld a, $80
	ldh [rSC], a
;> return
	ret

; unused: ldh a, [hSerialState] / cp 2 / ret nz / xor a / ldh [rIF], a / ei / ret
	db $f0, $cd, $fe, $02, $c0, $af, $e0, $0f, $fb, $c9, $ff, $ff, $ff, $ff, $ff, $ff
	db $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff
	db $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff

;@ def Boot()
;@ path: boot/vectors
;@ Cartridge entry point: the boot ROM jumps here after the logo.
;@ test: skip never returns
;@ sig: 7f119ac7
Boot::
;> goto(Entry)                      # hop over the cartridge header
	nop
	jp Entry


;@ asset: logo
;@ The Nintendo logo. The boot ROM scrolls this down the screen and refuses to
;@ start the cartridge unless these 48 bytes match its own copy.
;@ path: boot/header
HeaderLogo::
	db $ce, $ed, $66, $66, $cc, $0d, $00, $0b, $03, $73, $00, $83, $00, $0c, $00, $0d
	db $00, $08, $11, $1f, $88, $89, $00, $0e, $dc, $cc, $6e, $e6, $dd, $dd, $d9, $99
	db $bb, $bb, $67, $63, $6e, $0e, $ec, $cc, $dd, $dc, $99, $9f, $bb, $b9, $33, $3e

;@ asset: header range=$0100-$014F
;@ The cartridge header: entry point, logo, title, hardware and checksums.
;@ path: boot/header
HeaderTitle::
	db "TETRIS", $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

;@ path: boot/header
HeaderNewLicenseeCode::
	db $00, $00

;@ path: boot/header
HeaderSGBFlag::
	db $00

;@ path: boot/header
HeaderCartridgeType::
	db $00

;@ path: boot/header
HeaderROMSize::
	db $00

;@ path: boot/header
HeaderRAMSize::
	db $00

;@ path: boot/header
HeaderDestinationCode::
	db $00

;@ path: boot/header
HeaderOldLicenseeCode::
	db $01

;@ path: boot/header
HeaderMaskROMVersion::
	db $01

;@ path: boot/header
HeaderComplementCheck::
	db $0a

;@ path: boot/header
HeaderGlobalChecksum::
	db $16, $bf

;@ def Entry()
;@ path: boot/vectors
;@ First instruction after the header.
;@ test: skip never returns
;@ sig: 2e13df2b
Entry::
;> goto(Start)
	jp Start


;@ def ReadBGTileAtCoords() -> a
;@ path: gfx/tilemaps
;@ Unused. Returns the BG map tile under the OAM coordinates (hCoordY, hCoordX).
;@ The tile is read twice, each time right after HBlank starts, and the two
;@ reads are ANDed together.
;@ reads: hCoordY, hCoordX
;@ writes: hBGMapAddr
;@ clobbers: b, de, hl
;@ test: skip polls the LCD status
;@ sig: 2322b88a
ReadBGTileAtCoords::
;> tile_addr = CoordsToBGMapAddr()
	call CoordsToBGMapAddr

;> wait_hblank()
.waitHBlank1
	ldh a, [rSTAT]
	and $03
	jr nz, .waitHBlank1

;> first = mem[tile_addr]
	ld b, [hl]

;> wait_hblank()
.waitHBlank2
	ldh a, [rSTAT]
	and $03
	jr nz, .waitHBlank2

;> return first & mem[tile_addr]
	ld a, [hl]
	and b
	ret


;@ def AddScoreBCD(points: de, score: hl)
;@ path: lib/math
;@ Adds a 4-digit BCD number to a 6-digit BCD score (3 bytes, least
;@ significant first). The result is capped at 999999. Flags the score
;@ for redrawing.
;@ writes: hDrawBCDFlag
;@ clobbers: a, hl
;@ test: points = rand_bcd(2)
;@ test: score = rand_ram(3)
;@ test: fill_bcd(score, 3)
;@ sig: bbd0fe8b
AddScoreBCD::
;> s = bcd_to_int(mem[score]) + bcd_to_int(lo(points))                 # add + daa
	ld a, e
	add [hl]
	daa
;> mem[score] = to_bcd(s % 100)
	ld [hli], a
;> s = bcd_to_int(mem[score + 1]) + bcd_to_int(hi(points)) + s // 100   # adc + daa
	ld a, d
	adc [hl]
	daa
;> mem[score + 1] = to_bcd(s % 100)
	ld [hli], a
;> s = bcd_to_int(mem[score + 2]) + s // 100
	ld a, $00
	adc [hl]
	daa
;> mem[score + 2] = to_bcd(s % 100)
	ld [hl], a
;> hDrawBCDFlag = 1
	ld a, $01
	ldh [hDrawBCDFlag], a
;> if s >= 100:                              # carry out of the top digit: total > 999999
	ret nc

;>     bcd_write(score, 3, 999999)
	ld a, $99
	ld [hld], a
	ld [hld], a
	ld [hl], a
;>     return
	ret


;@ def VBlankHandler()
;@ path: system/interrupts
;@ VBlank interrupt. Starts a pending link-cable send, runs all per-frame
;@ screen updates and the sprite DMA, then tells the main loop a frame is done.
;@ reads: hSerialSendPending, hSerialRole, hSerialTx, wScoreDirty, hPiecePhase
;@ writes: hSerialSendPending, wScoreDirty, hDrawBCDFlag, hFrameCounter, hVBlankDone
;@ test: skip interrupt handler that drives the hardware
;@ sig: c65e6fe7
VBlankHandler::
;> # (all registers are saved and restored)
	push af
	push bc
	push de
	push hl
;> if hSerialSendPending and hSerialRole == SERIAL_MASTER:
	ldh a, [hSerialSendPending]
	and a
	jr z, .updates

	ldh a, [hSerialRole]
	cp SERIAL_MASTER
	jr nz, .updates

;>     hSerialSendPending = 0
	xor a
	ldh [hSerialSendPending], a
;>     rSB = hSerialTx
	ldh a, [hSerialTx]
	ldh [rSB], a
;>     rSC = 0x81                          # start the transfer on our clock
	ld hl, rSC
	ld [hl], $81

.updates
;> AnimateLineClear()
	call AnimateLineClear
;> # 18 small update routines, one call each
;> RefreshBoardRow0()
	call RefreshBoardRow0
;> RefreshBoardRow1()
	call RefreshBoardRow1
;> RefreshBoardRow2()
	call RefreshBoardRow2
;> RefreshBoardRow3()
	call RefreshBoardRow3
;> RefreshBoardRow4()
	call RefreshBoardRow4
;> RefreshBoardRow5()
	call RefreshBoardRow5
;> RefreshBoardRow6()
	call RefreshBoardRow6
;> RefreshBoardRow7()
	call RefreshBoardRow7
;> RefreshBoardRow8()
	call RefreshBoardRow8
;> RefreshBoardRow9()
	call RefreshBoardRow9
;> RefreshBoardRow10()
	call RefreshBoardRow10
;> RefreshBoardRow11()
	call RefreshBoardRow11
;> RefreshBoardRow12()
	call RefreshBoardRow12
;> RefreshBoardRow13()
	call RefreshBoardRow13
;> RefreshBoardRow14()
	call RefreshBoardRow14
;> RefreshBoardRow15()
	call RefreshBoardRow15
;> RefreshBoardRow16()
	call RefreshBoardRow16
;> RefreshBoardRow17()
	call RefreshBoardRow17
;> UpdateTally()
	call UpdateTally
;> OAMDMARoutine()                         # the copy in HRAM at hOAMDMA
	call hOAMDMA
;> CopyHighScoresToVRAM()
	call CopyHighScoresToVRAM
;> if wScoreDirty and hPiecePhase == 3:
	ld a, [wScoreDirty]
	and a
	jr z, .done

	ldh a, [hPiecePhase]
	cp $03
	jr nz, .done

;>     DrawScoreIfTypeA(vBGMap0 + 0x6D)
	ld hl, vBGMap0 + $6D
	call DrawScoreIfTypeA
;>     hDrawBCDFlag = 1                    # force the second copy to draw too
	ld a, $01
	ldh [hDrawBCDFlag], a
;>     DrawScoreIfTypeA(vBGMap1 + 0x6D)
	ld hl, vBGMap1 + $6D
	call DrawScoreIfTypeA
;>     wScoreDirty = 0
	xor a
	ld [wScoreDirty], a

.done
;> hFrameCounter += 1
	ld hl, hFrameCounter
	inc [hl]
;> rSCX = 0
	xor a
	ldh [rSCX], a
;> rSCY = 0
	ldh [rSCY], a
;> hVBlankDone = 1
	inc a
	ldh [hVBlankDone], a
;> return                                  # registers restored, reti
	pop hl
	pop de
	pop bc
	pop af
	reti


;@ def Start()
;@ path: boot
;@ Power-on start: clears WRAM bank 1 ($D000-$DFFF), then falls into SoftReset.
;@ test: skip never returns
;@ sig: 3b0b3c34
Start::
;> addr = WORK_RAM1 + 0xFFF                   # cleared from $DFFF downwards
	xor a
	ld hl, WORK_RAM1 + $FFF
;>@outer for _ in range(0x10):
	ld c, $10
;>@inner     for _ in range(0x100):
	ld b, $00

.clear
;>         mem[addr] = 0; addr -= 1
	ld [hld], a
;=@inner
	dec b
	jr nz, .clear

;=@outer
	dec c
	jr nz, .clear

;> SoftReset()                             # falls through

;@ def SoftReset()
;@ path: boot
;@ Initialises the hardware and all memory, then enters the main loop.
;@ The main loop also comes back here when A+B+Select+Start are held.
;@ writes: hGameType, hMusicType, hGameState, $FFA4, hUnused
;@ test: skip initialises the hardware and never returns
;@ sig: b4e5a2cf
SoftReset::
;>@rif rIF = 1                               # only the VBlank interrupt
	ld a, $01
;> disable_interrupts()
	di
;=@rif
	ldh [rIF], a
;> rIE = 1
	ldh [rIE], a
;> rSCY = 0
	xor a
	ldh [rSCY], a
;> rSCX = 0
	ldh [rSCX], a
;> hUnused = 0
	ldh [hUnused], a
;> rSTAT = 0
	ldh [rSTAT], a
;> rSB = 0
	ldh [rSB], a
;> rSC = 0
	ldh [rSC], a
;> rLCDC = 0x80                            # LCD on, everything else off
	ld a, $80
	ldh [rLCDC], a

;> wait_ly(0x94)                           # somewhere inside VBlank
.waitVBlank
	ldh a, [rLY]
	cp $94
	jr nz, .waitVBlank

;> rLCDC = 0x03                            # LCD off (safe during VBlank)
	ld a, $03
	ldh [rLCDC], a
;> rBGP = 0xE4                             # palettes
	ld a, $e4
	ldh [rBGP], a
;> rOBP0 = 0xE4
	ldh [rOBP0], a
;> rOBP1 = 0xC4
	ld a, $c4
	ldh [rOBP1], a
;> rNR52 = 0x80                            # sound on
	ld hl, rNR52
	ld a, $80
	ld [hld], a
;> rNR51 = 0xFF                            # all channels
	ld a, $ff
	ld [hld], a
;> rNR50 = 0x77                            # full volume
	ld [hl], $77
;> set_rom_bank(1)
	ld a, $01
	ld [rROMB0], a
;> reset_stack(WORK_RAM0 + 0xFFF)
	ld sp, WORK_RAM0 + $FFF
;> addr = WORK_RAM1 + 0xFFF                # clear the top of WRAM (the stack used so far), downwards
	xor a
	ld hl, WORK_RAM1 + $FFF
;>@stk for _ in range(0x100):
	ld b, $00

.clearStackPage
;>     mem[addr] = 0; addr -= 1
	ld [hld], a
;=@stk
	dec b
	jr nz, .clearStackPage

;> addr = WORK_RAM0 + 0xFFF                # clear WRAM bank 0 ($C000-$CFFF), downwards
	ld hl, WORK_RAM0 + $FFF
;>@w0o for _ in range(0x10):
	ld c, $10
;>@w0i     for _ in range(0x100):
	ld b, $00

.clearWRAM0
;>         mem[addr] = 0; addr -= 1
	ld [hld], a
;=@w0i
	dec b
	jr nz, .clearWRAM0

;=@w0o
	dec c
	jr nz, .clearWRAM0

;> addr = vTiles0 + 0x1FFF                 # clear all of VRAM, downwards
	ld hl, vTiles0 + $1FFF
;>@vro for _ in range(0x20):
	ld c, $20
	xor a
;>@vri     for _ in range(0x100):
	ld b, $00

.clearVRAM
;>         mem[addr] = 0; addr -= 1
	ld [hld], a
;=@vri
	dec b
	jr nz, .clearVRAM

;=@vro
	dec c
	jr nz, .clearVRAM

;> addr = OAM_START + 0xFF                 # clear OAM and the unusable area after it
	ld hl, OAM_START + $FF
;>@oam for _ in range(0x100):
	ld b, $00

.clearOAM
;>     mem[addr] = 0; addr -= 1
	ld [hld], a
;=@oam
	dec b
	jr nz, .clearOAM

;> addr = HRAM_START + 0x7E                # clear HRAM ($FF7F-$FFFE), downwards
	ld hl, HRAM_START + $7E
;>@hram for _ in range(0x80):
	ld b, $80

.clearHRAM
;>     mem[addr] = 0; addr -= 1
	ld [hld], a
;=@hram
	dec b
	jr nz, .clearHRAM

;>@dma for i in range(12):                 # the DMA routine must run from HRAM
	ld c, LOW(hOAMDMA)
	ld b, $0c
	ld hl, OAMDMARoutine

.copyDMARoutine
;>     mem[addr(hOAMDMA) + i] = mem[OAMDMARoutine + i]
	ld a, [hli]
	ldh [c], a
	inc c
;=@dma
	dec b
	jr nz, .copyDMARoutine

;> ClearBGMap0()
	call ClearBGMap0
;> InitSound()
	call InitSound
;> rIE = 0x09                              # VBlank + serial interrupts
	ld a, $09
	ldh [rIE], a
;> hGameType = GAME_TYPE_A
	ld a, GAME_TYPE_A
	ldh [hGameType], a
;> hMusicType = 0x1C
	ld a, $1c
	ldh [hMusicType], a
;> hGameState = 0x24                       # first state: the copyright screen
	ld a, $24
	ldh [hGameState], a
;> rLCDC = 0x80
	ld a, $80
	ldh [rLCDC], a
;> enable_interrupts()
	ei
;> rIF = 0
	xor a
	ldh [rIF], a
;> rWY = 0
	ldh [rWY], a
;> rWX = 0
	ldh [rWX], a
;> rTMA = 0
	ldh [rTMA], a

;> MainLoop()                              # falls through

;@ def MainLoop()
;@ path: boot
;@ The game's main loop: one iteration per frame, forever.
;@ reads: hJoyHeld, hTwoPlayer, hVBlankDone
;@ writes: hTimer1, hTimer2, hVBlankDone
;@ test: skip never returns
;@ sig: 77e8149d
MainLoop::
;>@loop for _ in forever():
;>     ReadJoypad()
	call ReadJoypad
;>     RunGameState()
	call RunGameState
;>     UpdateSound()
	call UpdateSound
;>     if (hJoyHeld & 0x0F) == 0x0F:       # A + B + Select + Start
	ldh a, [hJoyHeld]
	and $0f
	cp $0f
;>         goto(SoftReset)
	jp z, SoftReset

;>     timer = addr(hTimer1)               # hTimer1, then hTimer2
	ld hl, hTimer1
;>@tmr     for _ in range(2):
	ld b, $02

;>         if mem[timer]:
.timers
	ld a, [hl]
	and a
	jr z, .nextTimer

;>             mem[timer] -= 1
	dec [hl]

;>         timer += 1
.nextTimer
	inc l
;=@tmr
	dec b
	jr nz, .timers

;>     if hTwoPlayer:
	ldh a, [hTwoPlayer]
	and a
	jr z, .waitVBlank

;>         rIE = 0x09                      # VBlank + serial interrupts
	ld a, $09
	ldh [rIE], a

;>     while not hVBlankDone: pass         # set by VBlankHandler
.waitVBlank
	ldh a, [hVBlankDone]
	and a
	jr z, .waitVBlank

;>     hVBlankDone = 0
	xor a
	ldh [hVBlankDone], a
;=@loop
	jp MainLoop


;@ def RunGameState()
;@ path: boot
;@ Calls the handler for the current game state (once per frame).
;@ reads: hGameState
;@ test: hGameState = rand(0, 54)
;@ sig: 3d559786
RunGameState::
;> GameStateTable[hGameState]()
	ldh a, [hGameState]
	rst $28

GameStateTable::
	dw State00_Playing
	dw State01_GameOver
	dw State02_ShuttleLiftoff
	dw State03_ShuttleFlight
	dw State04_GameOverWait
	dw State05_TypeBTally
	dw State06_TitleScreenInit
	dw State07_TitleScreen
	dw State08_GameMenuInit
	dw State09_Nothing
	dw State0A_StartGame
	dw State0B_StartTally
	dw State0C_WaitButton
	dw State0D_GameOverScreen
	dw State0E_GameTypeMenu
	dw State0F_MusicMenu
	dw State10_TypeALevelInit
	dw State11_TypeALevelSelect
	dw State12_TypeBLevelInit
	dw State13_TypeBLevelSelect
	dw State14_TypeBHighSelect
	dw State15_NameEntry
	dw State16_VersusHeightInit
	dw State17_VersusHeightSelect
	dw State18_VersusRoundInit
	dw State19_VersusSync
	dw State1A_VersusPlaying
	dw State1B_VersusRoundOver
	dw State1C_VersusRoundStart
	dw State1D_VersusWon
	dw State1E_VersusLost
	dw State1F_VersusNextRound
	dw State20_VersusWonWait
	dw State21_VersusLostWait
	dw State22_DancersInit
	dw State23_Dancers
	dw State24_CopyrightScreen
	dw State25_CopyrightWait
	dw State26_ShuttleInit
	dw State27_ShuttleSmoke
	dw State28_ShuttleIgnition
	dw State29_ShuttleRelease
	dw State2A_VersusMenuInit
	dw State2B_VersusMusicMenu
	dw State2C_TypeMessage
	dw State2D_ShuttleEnd
	dw State2E_RocketInit
	dw State2F_RocketSmoke
	dw State30_RocketIgnition
	dw State31_RocketLiftoff
	dw State32_RocketFlight
	dw State33_RocketEnd
	dw State34_RocketWait
	dw State35_CopyrightWaitSkippable
	dw DoNothing

;@ def State24_CopyrightScreen()
;@ path: screens/copyright
;@ Game state $24 (the first one after boot): shows the copyright screen and
;@ prepares the fixed piece sequence for demo / 2-player games.
;@ writes: hTimer1, hGameState
;@ test: skip switches the LCD off
;@ sig: 00f70a57
State24_CopyrightScreen::
;> DisableLCD()
	call DisableLCD
;> LoadTitleTiles()
	call LoadTitleTiles
;> LoadScreen(CopyrightScreenTilemap)
	ld de, CopyrightScreenTilemap
	call LoadScreen
;> ClearShadowOAM()
	call ClearShadowOAM
;>@cp for i in range(0x100):
	ld hl, wPieceList
	ld de, DemoPieceList

.copy
;>     wPieceList[i] = mem[DemoPieceList + i]
	ld a, [de]
	ld [hli], a
	inc de
;=@cp
	ld a, h
	cp HIGH(wPieceList) + 1
	jr nz, .copy

;> rLCDC = 0xD3                                    # LCD on: BG, sprites, window map 1
	ld a, $d3
	ldh [rLCDC], a
;> hTimer1 = 250
	ld a, $fa
	ldh [hTimer1], a
;> hGameState = 0x25                               # State25_CopyrightWait
	ld a, $25
	ldh [hGameState], a
;> return
	ret


;@ def State25_CopyrightWait()
;@ path: screens/copyright
;@ Game state $25: keeps the copyright screen up for 250 frames, no skipping.
;@ reads: hTimer1
;@ writes: hTimer1, hGameState
;@ test: hTimer1 = rng.choice([0, 7])
;@ sig: b3be8ec8
State25_CopyrightWait::
;> if hTimer1 != 0: return
	ldh a, [hTimer1]
	and a
	ret nz

;> hTimer1 = 250
	ld a, $fa
	ldh [hTimer1], a
;> hGameState = 0x35                               # State35_CopyrightWaitSkippable
	ld a, $35
	ldh [hGameState], a
	ret


;@ def State35_CopyrightWaitSkippable()
;@ path: screens/copyright
;@ Game state $35: another 250 frames of copyright screen, but now any
;@ button skips to the title screen.
;@ reads: hJoyPressed, hTimer1
;@ writes: hGameState
;@ test: hJoyPressed = rng.choice([0, 0, 8])
;@ test: hTimer1 = rng.choice([0, 7])
;@ sig: 1837442f
State35_CopyrightWaitSkippable::
;> if not hJoyPressed:
	ldh a, [hJoyPressed]
	and a
	jr nz, .next

;>     if hTimer1 != 0:
	ldh a, [hTimer1]
	and a
;>         return
	ret nz

;> hGameState = 0x06                               # State06_TitleScreenInit
.next
	ld a, $06
	ldh [hGameState], a
;> return
	ret


;@ def State06_TitleScreenInit()
;@ path: screens/title
;@ Game state $06: resets the game variables and builds the title screen.
;@ Also prepares the board frame in wBGMap0Copy for the coming game.
;@ reads: hDemo
;@ writes: hDemoRecord, hPiecePhase, hClearAnimPhase, hCollision, hSpawnBlocked, hLines, hBoardCopyStage, hNameEntryPending, wMusicRequest, hGameState, hTimer1, hDemoCountdown, wShadowOAM
;@ test: skip switches the LCD off
;@ sig: 404a9c8b
State06_TitleScreenInit::
;> DisableLCD()
	call DisableLCD
;> hDemoRecord = 0
	xor a
	ldh [hDemoRecord], a
;> hPiecePhase = 0
	ldh [hPiecePhase], a
;> hClearAnimPhase = 0
	ldh [hClearAnimPhase], a
;> hCollision = 0
	ldh [hCollision], a
;> hSpawnBlocked = 0
	ldh [hSpawnBlocked], a
;> hLines = lo(hLines)                             # clears the top two digits
	ldh [hLines + 1], a
;> hBoardCopyStage = 0
	ldh [hBoardCopyStage], a
;> hNameEntryPending = 0
	ldh [hNameEntryPending], a
;> ClearClearedRows()
	call ClearClearedRows
;> ClearScoreData()
	call ClearScoreData
;> LoadTitleTiles()
	call LoadTitleTiles
;>@clr for i in range(0x400):
	ld hl, wBGMap0Copy

.clear
;>     wBGMap0Copy[i] = TILE_BLANK
	ld a, TILE_BLANK
	ld [hli], a
;=@clr
	ld a, h
	cp HIGH(wBGMap0Copy) + 4
	jr nz, .clear

;> DrawWallColumn(wBGMap0Copy + 0x01)              # left wall of the board
	ld hl, wBGMap0Copy + $01
	call DrawWallColumn
;> DrawWallColumn(wBGMap0Copy + 0x0C)              # right wall
	ld hl, wBGMap0Copy + $0C
	call DrawWallColumn
;>@flr for i in range(12):                         # floor
	ld hl, wBGMap0Copy + $241
	ld b, $0c
	ld a, TILE_WALL

.floor
;>     wBGMap0Copy[0x241 + i] = TILE_WALL
	ld [hli], a
;=@flr
	dec b
	jr nz, .floor

;> LoadScreen(TitleScreenTilemap)
	ld de, TitleScreenTilemap
	call LoadScreen
;> ClearShadowOAM()
	call ClearShadowOAM
;> wShadowOAM[0] = 0x80                            # the 1PLAYER/2PLAYER cursor
	ld hl, wShadowOAM
	ld [hl], $80
;> wShadowOAM[1] = 0x10
	inc l
	ld [hl], $10
;> wShadowOAM[2] = 0x58
	inc l
	ld [hl], $58
;> wMusicRequest = 3                               # title music
	ld a, $03
	ld [wMusicRequest], a
;> rLCDC = 0xD3
	ld a, $d3
	ldh [rLCDC], a
;> hGameState = 0x07                               # State07_TitleScreen
	ld a, $07
	ldh [hGameState], a
;> hTimer1 = 125
	ld a, $7d
	ldh [hTimer1], a
;> hDemoCountdown = 4
	ld a, $04
	ldh [hDemoCountdown], a
;> if hDemo:                                       # after a demo, the next one comes sooner
	ldh a, [hDemo]
	and a
;>     return
	ret nz

;> hDemoCountdown = 19
	ld a, $13
	ldh [hDemoCountdown], a
;> return
	ret

;@ def StartDemo()
;@ path: screens/demo
;@ Reached from the title screen when nobody pressed anything: sets up a demo
;@ game, alternating between type A (level 9) and type B (level 9, height 2).
;@ writes: hGameType, hTypeALevel, hTwoPlayer, hPieceListPos, hDemoButtons, hDemoInputTimer, hDemoInputHi, hDemoInputLo, hTypeBLevel, hTypeBHigh, hDemo, hGameState
;@ test: skip switches the LCD off
;@ sig: adddec9e
StartDemo::
;> hGameType = GAME_TYPE_A
	ld a, GAME_TYPE_A
	ldh [hGameType], a
;> hTypeALevel = 9
	ld a, $09
	ldh [hTypeALevel], a
;> hTwoPlayer = 0
	xor a
	ldh [hTwoPlayer], a
;> hPieceListPos = 0
	ldh [hPieceListPos], a
;> hDemoButtons = 0
	ldh [hDemoButtons], a
;> hDemoInputTimer = 0
	ldh [hDemoInputTimer], a
;> hDemoInputHi = 0x62                             # recorded input at $62B0
	ld a, $62
	ldh [hDemoInputHi], a
;> hDemoInputLo = 0xB0
	ld a, $b0
	ldh [hDemoInputLo], a
;>@if if hDemo == 2:                                  # last demo was type A: now type B
	ldh a, [hDemo]
	cp $02
;=@d2
	ld a, $02
;=@if
	jr nz, .setDemo

;>     hGameType = GAME_TYPE_B
	ld a, GAME_TYPE_B
	ldh [hGameType], a
;>     hTypeBLevel = 9
	ld a, $09
	ldh [hTypeBLevel], a
;>     hTypeBHigh = 2
	ld a, $02
	ldh [hTypeBHigh], a
;>     hDemoInputHi = 0x63                         # recorded input at $63B0
	ld a, $63
	ldh [hDemoInputHi], a
;>     hDemoInputLo = 0xB0
	ld a, $b0
	ldh [hDemoInputLo], a
;>     hPieceListPos = 0x11
	ld a, $11
	ldh [hPieceListPos], a
;>     hDemo = 1
	ld a, $01

.setDemo
	ldh [hDemo], a
;> else:
;>@d2     hDemo = 2
;> hGameState = 0x0A                               # State0A_StartGame: start the game
	ld a, $0a
	ldh [hGameState], a
;> DisableLCD()
	call DisableLCD
;> LoadGameTiles()
	call LoadGameTiles
;> LoadScreen(GameMusicTypeTilemap)
	ld de, GameMusicTypeTilemap
	call LoadScreen
;> ClearShadowOAM()
	call ClearShadowOAM
;> rLCDC = 0xD3
	ld a, $d3
	ldh [rLCDC], a
;> return
	ret

; unused: ld a, $ff / ldh [hDemoRecord], a / ret
	db $3e, $ff, $e0, $e9, $c9

;@ def State07_TitleScreen()
;@ path: screens/title
;@ Game state $07: the title screen. Select/Left/Right move the cursor between
;@ 1 PLAYER and 2 PLAYER, Start begins (holding Down: hard mode). It also
;@ listens on the link cable for a second Game Boy; idle long enough and the
;@ demo starts.
;@ reads: hTimer1, hDemoCountdown, hSerialDone, hSerialRole, hJoyPressed, hJoyHeld, hTwoPlayer
;@ writes: hTimer1, hDemoCountdown, hSerialDone, hTwoPlayer, hHardMode, hGameState, hTypeALevel, hTypeBLevel, hTypeBHigh, hDemo, wShadowOAM
;@ test: skip talks to the link cable
;@ sig: 65fda57e
State07_TitleScreen::
;> if hTimer1 == 0:
	ldh a, [hTimer1]
	and a
	jr nz, .listen

;>     hDemoCountdown -= 1
	ld hl, hDemoCountdown
	dec [hl]
;>     if hDemoCountdown == 0: goto(StartDemo)
	jr z, StartDemo

;>     hTimer1 = 125
	ld a, $7d
	ldh [hTimer1], a

;> Delay()
.listen
	call Delay
;> rSB = SERIAL_SLAVE                              # wait for a master, on its clock
	ld a, SERIAL_SLAVE
	ldh [rSB], a
;> rSC = 0x80
	ld a, $80
	ldh [rSC], a
;> if hSerialDone:
	ldh a, [hSerialDone]
	and a
	jr z, .buttons

;>     if hSerialRole: next_state = 0x2A          # the other Game Boy started: 2-player
	ldh a, [hSerialRole]
	and a
	jr nz, .start2Player

;>     else:
;>         hSerialDone = 0
	xor a
	ldh [hSerialDone], a
;>         hTwoPlayer = 0; wShadowOAM[1] = 0x10; return     # (.select1Player)
	jr .select1Player

;> else:
;>     buttons = hJoyPressed
.buttons
	ldh a, [hJoyPressed]
	ld b, a
;>     players = hTwoPlayer
	ldh a, [hTwoPlayer]
;>     if buttons & BTN_SELECT:
	bit 2, b
	jr nz, .toggle

;>@tog         hTwoPlayer = players ^ 1
;>@cur         wShadowOAM[1] = 0x60 if hTwoPlayer else 0x10
;>@ret         return
;>     if buttons & BTN_RIGHT:
	bit 4, b
	jr nz, .right

;>@r1         if players:
;>@r2             return
;>@r3         hTwoPlayer = 1; wShadowOAM[1] = 0x60; return  # (through the toggle code)
;>     if buttons & BTN_LEFT:
	bit 5, b
	jr nz, .left

;>@l1         if not players:
;>@l2             return
;>@l3         hTwoPlayer = 0; wShadowOAM[1] = 0x10; return  # (.select1Player)
;>     if not buttons & BTN_START:
	bit 3, b
;>         return
	ret z

;>@np     if not players:
	and a
;=@n8
	ld a, $08
;=@np
	jr z, .start1Player

;>@hm1         if hJoyHeld & BTN_DOWN:
;>@hm2             hHardMode = hJoyHeld
;>@n8         next_state = 0x08                   # State08_GameMenuInit: game type menu
;>     else:
;>         if buttons != BTN_START:
	ld a, b
	cp $08
;>             return
	ret nz

;>         if hSerialRole != SERIAL_MASTER:
	ldh a, [hSerialRole]
	cp SERIAL_MASTER
	jr z, .start2Player

;>             rSB = SERIAL_MASTER                # call the other Game Boy, on our clock
	ld a, SERIAL_MASTER
	ldh [rSB], a
;>             rSC = 0x81
	ld a, $81
	ldh [rSC], a

;>             while not hSerialDone: pass
.waitSerial
	ldh a, [hSerialDone]
	and a
	jr z, .waitSerial

;>             if not hSerialRole: hTwoPlayer = 0; wShadowOAM[1] = 0x10; return   # nobody answered (.select1Player)
	ldh a, [hSerialRole]
	and a
	jr z, .select1Player

;>         next_state = 0x2A
.start2Player
	ld a, $2a

;> hGameState = next_state
.setState
	ldh [hGameState], a
;> hTimer1 = 0
	xor a
	ldh [hTimer1], a
;> hTypeALevel = 0
	ldh [hTypeALevel], a
;> hTypeBLevel = 0
	ldh [hTypeBLevel], a
;> hTypeBHigh = 0
	ldh [hTypeBHigh], a
;> hDemo = 0
	ldh [hDemo], a
;> return
	ret

;=@hm1
.start1Player
	push af
	ldh a, [hJoyHeld]
	bit 7, a
	jr z, .noHardMode

;=@hm2
	ldh [hHardMode], a

;=@n8
.noHardMode
	pop af
	jr .setState

;=@tog
.toggle
	xor $01

.setPlayers
	ldh [hTwoPlayer], a
;=@cur
	and a
	ld a, $10
	jr z, .setCursor

	ld a, $60

.setCursor
	ld [wShadowOAM + 1], a
;=@ret
	ret

;=@r1
.right
	and a
;=@r2
	ret nz

;=@r3
	xor a
	jr .toggle

;=@l1
.left
	and a
;=@l2
	ret z

;=@l3
.select1Player
	xor a
	jr .setPlayers

;@ def DemoCheckEnd()
;@ path: screens/demo
;@ During a demo: Start (the real button) or the end of the demo's piece
;@ sequence returns to the title screen.
;@ reads: hDemo, hJoyPressed, hPieceListPos
;@ writes: rSB, rSC, hGameState
;@ test: hDemo = rng.choice([0, 1, 2])
;@ test: hJoyPressed = rng.choice([0, 0, BTN_START])
;@ test: hPieceListPos = rng.choice([0x10, 0x1D, 0x05])
;@ sig: 33f138a9
DemoCheckEnd::
;> if not hDemo:
	ldh a, [hDemo]
	and a
;>     return
	ret z

;> Delay()
	call Delay
;> rSB = 0
	xor a
	ldh [rSB], a
;> rSC = 0x80
	ld a, $80
	ldh [rSC], a
;> if hJoyPressed & BTN_START:
	ldh a, [hJoyPressed]
	bit 3, a
	jr z, .checkEnd

;>     rSB = 0x33
	ld a, $33
	ldh [rSB], a
;>     rSC = 0x81
	ld a, $81
	ldh [rSC], a
;>     hGameState = 0x06                            # back to the title screen
	ld a, $06
	ldh [hGameState], a
;>     return
	ret

;> if hDemo == 2:                                   # where the demo's pieces run out
.checkEnd
	ld hl, hPieceListPos
	ldh a, [hDemo]
	cp $02
;>     end = 0x10
	ld b, $10
;> else:
	jr z, .compare

;>     end = 0x1D
	ld b, $1d

;> if hPieceListPos != end:
.compare
	ld a, [hl]
	cp b
;>     return
	ret nz

;> hGameState = 0x06                                # demo pieces used up
	ld a, $06
	ldh [hGameState], a
;> return
	ret


;@ def DemoPlayback()
;@ path: screens/demo
;@ During a demo: replaces the input with the recorded one (pairs of buttons
;@ and duration at hDemoInputHi:hDemoInputLo) and saves the real buttons.
;@ reads: hDemo, hDemoRecord, hDemoInputTimer, hDemoInputHi, hDemoInputLo, hDemoButtons, hJoyHeld
;@ writes: hDemoInputTimer, hJoyPressed, hDemoButtons, hDemoInputHi, hDemoInputLo, hRealJoyHeld, hJoyHeld
;@ test: hDemo = rng.choice([0, 1])
;@ test: hDemoRecord = rng.choice([0, 0, 0xFF])
;@ test: hDemoInputTimer = rng.choice([0, 0, 4])
;@ test: hDemoInputHi = 0x62
;@ test: hDemoInputLo = rand(0xB0, 0xFE)
;@ sig: 8092aad7
DemoPlayback::
;> if not hDemo:
	ldh a, [hDemo]
	and a
;>     return
	ret z

;> if hDemoRecord == 0xFF:
	ldh a, [hDemoRecord]
	cp $ff
;>     return
	ret z

;> if hDemoInputTimer:
	ldh a, [hDemoInputTimer]
	and a
	jr z, .next

;>     hDemoInputTimer -= 1
	dec a
	ldh [hDemoInputTimer], a
;>@np     hJoyPressed = 0
	jr .noPress

;>@else else:                                            # next recorded input
;>     p = hDemoInputHi << 8 | hDemoInputLo
.next
	ldh a, [hDemoInputHi]
	ld h, a
	ldh a, [hDemoInputLo]
	ld l, a
;>     buttons = mem[p]
	ld a, [hli]
	ld b, a
;>     hJoyPressed = buttons & ~hDemoButtons
	ldh a, [hDemoButtons]
	xor b
	and b
	ldh [hJoyPressed], a
;>     hDemoButtons = buttons
	ld a, b
	ldh [hDemoButtons], a
;>     hDemoInputTimer = mem[p + 1]
	ld a, [hli]
	ldh [hDemoInputTimer], a
;>     hDemoInputHi = hi(p + 2)
	ld a, h
	ldh [hDemoInputHi], a
;>     hDemoInputLo = lo(p + 2)
	ld a, l
	ldh [hDemoInputLo], a
;=@else
	jr .hold

;=@np
.noPress
	xor a
	ldh [hJoyPressed], a

;> hRealJoyHeld = hJoyHeld
.hold
	ldh a, [hJoyHeld]
	ldh [hRealJoyHeld], a
;> hJoyHeld = hDemoButtons
	ldh a, [hDemoButtons]
	ldh [hJoyHeld], a
;> return
	ret

; unused: xor a / ldh [hDemoButtons], a / jr DemoPlayback.noPress-ish / ret
	db $af, $e0, $ed, $18, $ef, $c9

;@ def DemoRecord()
;@ path: screens/demo
;@ Development leftover: with hDemoRecord = $FF, a "demo" records the
;@ player's input (buttons, duration) at hDemoInputHi:hDemoInputLo - which
;@ points into ROM, so on a real cartridge the writes go nowhere.
;@ reads: hDemo, hDemoRecord, hJoyHeld, hDemoButtons, hDemoInputTimer, hDemoInputHi, hDemoInputLo
;@ writes: hDemoInputHi, hDemoInputLo, hDemoButtons, hDemoInputTimer
;@ test: hDemo = rng.choice([0, 1])
;@ test: hDemoRecord = rng.choice([0, 0xFF, 0xFF])
;@ test: hJoyHeld = rng.choice([0, 1])
;@ test: hDemoButtons = rng.choice([0, 1])
;@ test: hDemoInputHi = 0xC4
;@ sig: a0904dd2
DemoRecord::
;> if not hDemo:
	ldh a, [hDemo]
	and a
;>     return
	ret z

;> if hDemoRecord != 0xFF:
	ldh a, [hDemoRecord]
	cp $ff
;>     return
	ret nz

;> if hJoyHeld == hDemoButtons:
	ldh a, [hJoyHeld]
	ld b, a
	ldh a, [hDemoButtons]
	cp b
	jr z, .same

;>@inc     hDemoInputTimer += 1
;>@same     return
;> p = hDemoInputHi << 8 | hDemoInputLo
	ldh a, [hDemoInputHi]
	ld h, a
	ldh a, [hDemoInputLo]
	ld l, a
;> mem[p] = hDemoButtons
	ldh a, [hDemoButtons]
	ld [hli], a
;> mem[p + 1] = hDemoInputTimer
	ldh a, [hDemoInputTimer]
	ld [hli], a
;> hDemoInputHi = hi(p + 2)
	ld a, h
	ldh [hDemoInputHi], a
;> hDemoInputLo = lo(p + 2)
	ld a, l
	ldh [hDemoInputLo], a
;> hDemoButtons = hJoyHeld
	ld a, b
	ldh [hDemoButtons], a
;> hDemoInputTimer = 0
	xor a
	ldh [hDemoInputTimer], a
;> return
	ret

;=@inc
.same
	ldh a, [hDemoInputTimer]
	inc a
	ldh [hDemoInputTimer], a
;=@same
	ret


;@ def DemoRestoreInput()
;@ path: screens/demo
;@ End of a demo frame: gives the player's real buttons back.
;@ reads: hDemo, hDemoRecord, hRealJoyHeld
;@ writes: hJoyHeld
;@ test: hDemo = rng.choice([0, 1])
;@ test: hDemoRecord = rng.choice([0, 0xFF])
;@ sig: f8892a7e
DemoRestoreInput::
;> if not hDemo:
	ldh a, [hDemo]
	and a
;>     return
	ret z

;> if hDemoRecord:
	ldh a, [hDemoRecord]
	and a
;>     return
	ret nz

;> hJoyHeld = hRealJoyHeld
	ldh a, [hRealJoyHeld]
	ldh [hJoyHeld], a
;> return
	ret

;=@State2A_VersusMenuInit.listen
; part of State2A_VersusMenuInit (the 2-player menu): the slave starts listening
VersusMenuSlaveListen:
	ld hl, rSC
	set 7, [hl]
	jr State2A_VersusMenuInit.showMenu

;@ def State2A_VersusMenuInit()
;@ path: versus/menu
;@ Game state $2A (link established): the music menu for a 2-player game.
;@ Only the master chooses; the slave mirrors it.
;@ reads: hSerialRole
;@ writes: hSerialState, wObjects, hSerialSendPending, rSB, hSerialTx, hLineClearKind, hGarbageIncoming, hGarbagePending, hGarbageAdded, hVersusGoalReached, hBoardCopyStage, hGameState
;@ test: skip switches the LCD off, talks to the link cable
;@ sig: 0027d5b4
State2A_VersusMenuInit::
;> hSerialState = 3
	ld a, $03
	ldh [hSerialState], a
;> if hSerialRole != SERIAL_MASTER:
	ldh a, [hSerialRole]
	cp SERIAL_MASTER
	jr nz, VersusMenuSlaveListen
;>@listen     rSC |= 0x80                           # the slave starts listening (VersusMenuSlaveListen)

;> ShowGameMenu()
.showMenu:
	call ShowGameMenu
;> wObjects[0x10] = 0x80                            # no game type cursor
	ld a, $80
	ld [wObjects + $10], a
;> DrawTwoObjects()
	call DrawTwoObjects
;> hSerialSendPending = 0                           # (a is 0 after DrawTwoObjects)
	ldh [hSerialSendPending], a
;> rSB = 0
	xor a
	ldh [rSB], a
;> hSerialTx = 0
	ldh [hSerialTx], a
;> hLineClearKind = 0
	ldh [hLineClearKind], a
;> hGarbageIncoming = 0
	ldh [hGarbageIncoming], a
;> hGarbagePending = 0
	ldh [hGarbagePending], a
;> hGarbageAdded = 0
	ldh [hGarbageAdded], a
;> hVersusGoalReached = 0
	ldh [hVersusGoalReached], a
;> hBoardCopyStage = 0
	ldh [hBoardCopyStage], a
;> InitSound()
	call InitSound
;> hGameState = 0x2B
	ld a, $2b
	ldh [hGameState], a
;> return
	ret


;@ def State2B_VersusMusicMenu()
;@ path: versus/menu
;@ Game state $2B: the master uses the normal music menu and sends its
;@ choice every frame; the slave plays whatever it receives. $50 (the master
;@ pressed Start or A) moves both to the height select (state $16).
;@ reads: hSerialRole, hJoyPressed, hMusicChanged, hSerialDone, hSerialRx, hSerialTx, hMusicType
;@ writes: hMusicChanged, hSerialDone, hSerialTx, hMusicType, hSerialSendPending, hGameState
;@ test: skip talks to the link cable
;@ sig: 495764ac
State2B_VersusMusicMenu::
;> if hSerialRole == SERIAL_MASTER:
	ldh a, [hSerialRole]
	cp SERIAL_MASTER
	jr z, .masterInput

;>@mi1     if not hJoyPressed & (BTN_A | BTN_START):
;>@mi2         State0F_MusicMenu()
;> elif hMusicChanged:
	ldh a, [hMusicChanged]
	and a
	jr z, .exchange

;>     hMusicChanged = 0
	xor a
	ldh [hMusicChanged], a
;>     PlaceMusicCursor(addr(wObjects) + 1)
	ld de, wObjects + $01
	call PlaceMusicCursor
;>     PlaySelectedMusic()
	call PlaySelectedMusic
;>     DrawTwoObjects()
	call DrawTwoObjects
	jr .exchange

;=@mi1
.masterInput:
	ldh a, [hJoyPressed]
	bit 0, a
	jr nz, .exchange

	bit 3, a
	jr nz, .exchange

;=@mi2
	call State0F_MusicMenu

;> if hSerialRole == SERIAL_MASTER:
.exchange:
	ldh a, [hSerialRole]
	cp SERIAL_MASTER
	jr z, .masterExchange

;>@m1     if hJoyPressed & (BTN_START | BTN_A):
;>@m2         hSerialTx = 0x50; hSerialSendPending = 1; return     # (on at .send)
;>@m3     if not hSerialDone:
;>@m4         return
;>@m5     hSerialDone = 0
;>@m6     if hSerialTx == 0x50: ClearShadowOAM(); hGameState = 0x16; return    # (.startHeightSelect)
;>@m7     hSerialTx = hMusicType
;>@m8     hSerialSendPending = 1
;>@m9     return
;> else:
;>     if not hSerialDone:
	ldh a, [hSerialDone]
	and a
;>         return
	ret z

;>     hSerialDone = 0
	xor a
	ldh [hSerialDone], a
;>     hSerialTx = 0x39
	ld a, $39
	ldh [hSerialTx], a
;>     if hSerialRx == 0x50:
	ldh a, [hSerialRx]
	cp $50
	jr z, .startHeightSelect

;>@hs1         ClearShadowOAM()
;>@hs2         hGameState = 0x16
;>@hs3         return
;>     if hSerialRx == hMusicType:
	ld b, a
	ldh a, [hMusicType]
	cp b
;>         return
	ret z

;>     hMusicType = hSerialRx
	ld a, b
	ldh [hMusicType], a
;>     hMusicChanged = 1
	ld a, $01
	ldh [hMusicChanged], a
;>     return
	ret

;=@m1
.masterExchange:
	ldh a, [hJoyPressed]
	bit 3, a
	jr nz, .sendStart

	bit 0, a
	jr nz, .sendStart

;=@m3
	ldh a, [hSerialDone]
	and a
;=@m4
	ret z

;=@m5
	xor a
	ldh [hSerialDone], a
;=@m6
	ldh a, [hSerialTx]
	cp $50
	jr z, .startHeightSelect

;=@m7
	ldh a, [hMusicType]

.send:
	ldh [hSerialTx], a
;=@m8
	ld a, $01
	ldh [hSerialSendPending], a
;=@m9
	ret

;=@hs1
.startHeightSelect:
	call ClearShadowOAM
;=@hs2
	ld a, $16
	ldh [hGameState], a
;=@hs3
	ret

;=@m2
.sendStart:
	ld a, $50
	jr .send

;=@State16_VersusHeightInit.listen
; part of State16_VersusHeightInit: the slave starts listening
VersusHeightSlaveListen:
	ld hl, rSC
	set 7, [hl]
	jr State16_VersusHeightInit.setup

;@ def State16_VersusHeightInit()
;@ path: versus/menu
;@ Game state $16: the master deals the piece sequence for both players,
;@ then the height select screen is built (Mario and Luigi faces, one
;@ cursor each). From the second round on it goes straight to the round.
;@ reads: hSerialRole, hVersusNextRound
;@ writes: hSerialState, wPieceList, hSerialSendPending, rSB, hSerialTx, hLineClearKind, hGarbageIncoming, hGarbagePending, hGarbageAdded, hVersusGoalReached, hBoardCopyStage, hSerialDone, wGarbageRow, hVersusWins, hVersusLosses, hAdvantageMe, hAdvantageOpponent, hDeuce, hGameState
;@ test: skip switches the LCD off, talks to the link cable
;@ sig: b561aa44
State16_VersusHeightInit::
;> hSerialState = 3
	ld a, $03
	ldh [hSerialState], a
;> if hSerialRole != SERIAL_MASTER:
	ldh a, [hSerialRole]
	cp SERIAL_MASTER
	jr nz, VersusHeightSlaveListen
;>@listen     rSC |= 0x80                           # the slave starts listening (VersusHeightSlaveListen)

;> else:                                            # the master deals for both
;>     RollListPiece()
	call RollListPiece
;>     RollListPiece()
	call RollListPiece
;>     RollListPiece()
	call RollListPiece
;>@deal     for i in range(256):
	ld b, $00
	ld hl, wPieceList

.dealPieces:
;>         wPieceList[i] = RollListPiece()
	call RollListPiece
	ld [hli], a
;=@deal
	dec b
	jr nz, .dealPieces

;> DisableLCD()
.setup:
	call DisableLCD
;> LoadGameTiles()
	call LoadGameTiles
;> LoadScreen(VersusSetupTilemap)
	ld de, VersusSetupTilemap
	call LoadScreen
;> ClearShadowOAM()
	call ClearShadowOAM
;> FillBoard(TILE_BLANK)
	ld a, TILE_BLANK
	call FillBoard
;> hSerialSendPending = 3
	ld a, $03
	ldh [hSerialSendPending], a
;> rSB = 0
	xor a
	ldh [rSB], a
;> hSerialTx = 0
	ldh [hSerialTx], a
;> hLineClearKind = 0
	ldh [hLineClearKind], a
;> hGarbageIncoming = 0
	ldh [hGarbageIncoming], a
;> hGarbagePending = 0
	ldh [hGarbagePending], a
;> hGarbageAdded = 0
	ldh [hGarbageAdded], a
;> hVersusGoalReached = 0
	ldh [hVersusGoalReached], a
;> hBoardCopyStage = 0
	ldh [hBoardCopyStage], a
;> hSerialDone = 0
	ldh [hSerialDone], a
;>@gr for i in range(10):
	ld hl, wGarbageRow
	ld b, $0a
	ld a, $28

.garbageRow:
;>     wGarbageRow[i] = 0x28
	ld [hli], a
;=@gr
	dec b
	jr nz, .garbageRow

;> if hVersusNextRound: goto(VersusStartRound)              # later rounds: no height select
	ldh a, [hVersusNextRound]
	and a
	jp nz, VersusStartRound

;> PlaySelectedMusic()
	call PlaySelectedMusic
;> rLCDC = 0xD3
	ld a, $d3
	ldh [rLCDC], a
;> CopyBytesB(addr(wShadowOAM) + 0x80, VersusFaces, 32)   # Mario and Luigi
	ld hl, wShadowOAM + $80
	ld de, VersusFaces
	ld b, $20
	call CopyBytesB
;> SetupObjects(wObjects, VersusMenuObjects, 2)     # their height cursors
	ld hl, wObjects
	ld de, VersusMenuObjects
	ld c, $02
	call SetupObjects
;> PlaceHeightCursors()
	call PlaceHeightCursors
;> DrawTwoObjects()
	call DrawTwoObjects
;> hVersusWins = 0
	xor a
	ldh [hVersusWins], a
;> hVersusLosses = 0
	ldh [hVersusLosses], a
;> hAdvantageMe = 0
	ldh [hAdvantageMe], a
;> hAdvantageOpponent = 0
	ldh [hAdvantageOpponent], a
;> hDeuce = 0
	ldh [hDeuce], a
;> hGameState = 0x17
	ld a, $17
	ldh [hGameState], a
;> return
	ret
VersusFaces::
	db $40, $28, $ae, $00, $40, $30, $ae, $20, $48, $28, $af, $00, $48, $30, $af, $20
	db $78, $28, $c0, $00, $78, $30, $c0, $20, $80, $28, $c1, $00, $80, $30, $c1, $20

;@ def CopyBytesB(dest: hl, src: de, count: b)
;@ path: lib/memory
;@ Copies `count` bytes (0 = 256) from src to dest.
;@ clobbers: a, b, de, hl
;@ test: dest = rand_ram(256)
;@ test: src = rand(0x0000, 0x7000)
;@ test: count = rand(0, 255)
;@ sig: 309e9060
CopyBytesB::
;>@lp for i in range(count or 256):
;>     mem[dest + i] = mem[src + i]
	ld a, [de]
	ld [hli], a
	inc de
;=@lp
	dec b
	jr nz, CopyBytesB

;> return
	ret


;@ def State17_VersusHeightSelect()
;@ path: versus/menu
;@ Game state $17: both players pick a handicap height at the same time;
;@ each side sends its own value and receives the other's. The master's
;@ Start ($60) begins the round.
;@ reads: hSerialRole, hSerialDone, hSerialRx, hSerialTx, hJoyPressed, hMasterHeight, hSlaveHeight
;@ writes: hMasterHeight, hSlaveHeight, hSerialTx, hSerialDone, hSerialSendPending, wSFXRequest
;@ test: skip talks to the link cable
;@ sig: 0fe69825
State17_VersusHeightSelect::
;> if hSerialRole != SERIAL_MASTER:
	ldh a, [hSerialRole]
	cp SERIAL_MASTER
	jr z, .master

;>     if hSerialDone:
	ldh a, [hSerialDone]
	and a
	jr z, .slaveCursor

;>         if hSerialRx == 0x60: ClearShadowOAM(); return VersusStartRound()   # (.begin)
	ldh a, [hSerialRx]
	cp $60
	jr z, .begin

;>         if hSerialRx < 6:
	cp $06
	jr nc, .sendHeight

;>             hMasterHeight = hSerialRx
	ldh [hMasterHeight], a

;>         hSerialTx = hSlaveHeight
.sendHeight:
	ldh a, [hSlaveHeight]
	ldh [hSerialTx], a
;>         hSerialDone = 0
	xor a
	ldh [hSerialDone], a

;>     buttons = BlinkObject(addr(wObjects) + 0x10)
.slaveCursor:
	ld de, wObjects + $10
	call BlinkObject
;>     mine = addr(hSlaveHeight)
	ld hl, hSlaveHeight
;=@else
	jr HeightSelectExchange.edit

;>@else else:                                       # (the slave jumps over this to the height edit)
;>     if hJoyPressed & BTN_START:
.master:
	ldh a, [hJoyPressed]
	bit 3, a
	jr z, .masterReceive

;>         send = 0x60                              # begin
	ld a, $60
	jr HeightSelectExchange.send

;>     elif not hSerialDone:
;>         send = None
.masterReceive:
	ldh a, [hSerialDone]
	and a
	jr z, HeightSelectExchange.masterCursor

;>     elif hSerialTx == 0x60:
	ldh a, [hSerialTx]
	cp $60
	jr nz, HeightSelectExchange

;>         ClearShadowOAM()
.begin:
	call ClearShadowOAM
;>         return VersusStartRound()                # (falls through into it)
;>     else:                                        # the rest is HeightSelectExchange, inside VersusStartRound
;>@rx         if hSerialRx < 6:
;>@rx2             hSlaveHeight = hSerialRx
;>@mine         send = hMasterHeight
;>@sendif     if send is not None:
;>@tx         hSerialTx = send
;>@done         hSerialDone = 0
;>@pend         hSerialSendPending = 1
;>@cursor     buttons = BlinkObject(addr(wObjects))
;>@mine2     mine = addr(hMasterHeight)
;>@edit height = mem[mine]
;> new = None
;>@right if buttons & BTN_RIGHT:
;>@r1     if height != 5:
;>@r2         new = height + 1
;>@left elif buttons & BTN_LEFT:
;>@l1     if height != 0:
;>@l2         new = height - 1
;>@up elif buttons & BTN_UP:
;>@u1     if height >= 3:
;>@u2         new = height - 3
;>@down elif buttons & BTN_DOWN:
;>@d1     if height < 3:
;>@d2         new = height + 3
;>@set if new is not None:
;>@store     mem[mine] = new
;>@sfx     wSFXRequest = 1
;>@place PlaceHeightCursors()
;>@draw DrawTwoObjects()
;>@ret return

;@ def VersusStartRound()
;@ path: versus/menu
;@ Starts a round: the first time via the round setup state ($18), later
;@ directly. The master fills the lower board with garbage (6 levels of 2 rows),
;@ which the sync later sends to the slave. (This unit also holds the height
;@ grid edit of State17_VersusHeightSelect.)
;@ reads: hVersusNextRound, hSerialRole, hMasterHeight, hSerialRx
;@ writes: hGameState, hTemp, hSerialDone, hSerialSendPending, hSerialTx, hSlaveHeight, wSFXRequest
;@ test: skip part of the link cable protocol
;@ sig: 47e80457
VersusStartRound::
;> if not hVersusNextRound:
	ldh a, [hVersusNextRound]
	and a
	jr nz, .laterRound

;>     hGameState = 0x18
	ld a, $18
	ldh [hGameState], a
;>     if hSerialRole != SERIAL_MASTER:
	ldh a, [hSerialRole]
	cp SERIAL_MASTER
;>         return
	ret nz

;>     hTemp = 0
	xor a
	ldh [hTemp], a
;>     GenerateGarbage(6, wBGMap0Copy + 0x1A2, 0xFFE0)   # $FFE0 = -32
	ld a, $06
	ld de, -32
	ld hl, wBGMap0Copy + $1A2
	call GenerateGarbage
;>     return
	ret

;> if hSerialRole != SERIAL_MASTER: goto(VersusRoundSetup)
.laterRound:
	ldh a, [hSerialRole]
	cp SERIAL_MASTER
	jp nz, VersusRoundSetup

;> hTemp = 0
	xor a
	ldh [hTemp], a
;> GenerateGarbage(6, wBGMap0Copy + 0x1A2, 0xFFE0)
	ld a, $06
	ld de, -32
	ld hl, wBGMap0Copy + $1A2
	call GenerateGarbage
;> goto(VersusRoundSetup)
	jp VersusRoundSetup

;=@State17_VersusHeightSelect.rx
; --- the rest of State17_VersusHeightSelect ---
HeightSelectExchange:
	ldh a, [hSerialRx]
	cp $06
	jr nc, .sendMine

;=@State17_VersusHeightSelect.rx2
	ldh [hSlaveHeight], a

;=@State17_VersusHeightSelect.mine
.sendMine:
	ldh a, [hMasterHeight]

;=@State17_VersusHeightSelect.tx
.send:
	ldh [hSerialTx], a
;=@State17_VersusHeightSelect.done
	xor a
	ldh [hSerialDone], a
;=@State17_VersusHeightSelect.pend
	inc a
	ldh [hSerialSendPending], a

;=@State17_VersusHeightSelect.cursor
.masterCursor:
	ld de, wObjects
	call BlinkObject
;=@State17_VersusHeightSelect.mine2
	ld hl, hMasterHeight

;=@State17_VersusHeightSelect.edit
.edit:
	ld a, [hl]
;=@State17_VersusHeightSelect.right
	bit 4, b
	jr nz, .right

;=@State17_VersusHeightSelect.left
	bit 5, b
	jr nz, .left

;=@State17_VersusHeightSelect.up
	bit 6, b
	jr nz, .up

;=@State17_VersusHeightSelect.down
	bit 7, b
	jr z, .draw

;=@State17_VersusHeightSelect.d1
	cp $03
	jr nc, .draw

;=@State17_VersusHeightSelect.d2
	add $03
	jr .set

;=@State17_VersusHeightSelect.r1
.right:
	cp $05
	jr z, .draw

;=@State17_VersusHeightSelect.r2
	inc a

;=@State17_VersusHeightSelect.store
.set:
	ld [hl], a
;=@State17_VersusHeightSelect.sfx
	ld a, $01
	ld [wSFXRequest], a

;=@State17_VersusHeightSelect.place
.draw:
	call PlaceHeightCursors
;=@State17_VersusHeightSelect.draw
	call DrawTwoObjects
;=@State17_VersusHeightSelect.ret
	ret

;=@State17_VersusHeightSelect.l1
.left:
	and a
	jr z, .draw

;=@State17_VersusHeightSelect.l2
	dec a
	jr .set

;=@State17_VersusHeightSelect.u1
.up:
	cp $03
	jr c, .draw

;=@State17_VersusHeightSelect.u2
	sub $03
	jr .set
MasterHeightPositions::
	db $40, $60, $40, $70, $40, $80, $50, $60, $50, $70, $50, $80

; (y, x) of the slave's height cursor for heights 0-5
SlaveHeightPositions::
	db $78, $60, $78, $70
	db $78, $80, $88, $60, $88, $70, $88, $80

;@ def PlaceHeightCursors()
;@ path: versus/menu
;@ Positions both height cursors of the 2-player menu (digit sprites).
;@ reads: hMasterHeight, hSlaveHeight
;@ test: hMasterHeight = rand(0, 5)
;@ test: hSlaveHeight = rand(0, 5)
;@ sig: 436bdaeb
PlaceHeightCursors::
;> SetupObjectFromTable(hMasterHeight, MasterHeightPositions, addr(wObjects) + 0x01)
	ldh a, [hMasterHeight]
	ld de, wObjects + $01
	ld hl, MasterHeightPositions
	call SetupObjectFromTable
;> SetupObjectFromTable(hSlaveHeight, SlaveHeightPositions, addr(wObjects) + 0x11)
	ldh a, [hSlaveHeight]
	ld de, wObjects + $11
	ld hl, SlaveHeightPositions
	call SetupObjectFromTable
;> return
	ret


;@ def State18_VersusRoundInit()
;@ path: versus/setup
;@ Game state $18: switches the LCD off, then VersusRoundSetup.
;@ test: skip switches the LCD off
;@ sig: c6075059
State18_VersusRoundInit::
;> DisableLCD()
	call DisableLCD
;> VersusRoundSetup()                               # falls through

;@ def VersusRoundSetup()
;@ path: versus/setup
;@ Prepares a 2-player round like State0A_StartGame does for one player:
;@ level 1, 30 lines to clear (counted down like type B), the 2-player
;@ screen, the player's face in the corner and its height.
;@ reads: hSerialRole, hMasterHeight, hSlaveHeight
;@ writes: wObjects, hPiecePhase, hClearAnimPhase, hCollision, hSpawnBlocked, hLines, hSerialDone, rSB, hSerialSendPending, hSerialRx, hSerialTx, hRoundResult, hBoardCopyStage, hLevel, hTwoPlayer, hTemp, hGameType, rLCDC, hGameState, hSerialState
;@ test: skip part of the link cable protocol
;@ sig: d3a53746
VersusRoundSetup::
;> wObjects[0x10] = 0
	xor a
	ld [wObjects + $10], a
;> hPiecePhase = 0
	ldh [hPiecePhase], a
;> hClearAnimPhase = 0
	ldh [hClearAnimPhase], a
;> hCollision = 0
	ldh [hCollision], a
;> hSpawnBlocked = 0
	ldh [hSpawnBlocked], a
;> hLines = lo(hLines)
	ldh [hLines + 1], a
;> hSerialDone = 0
	ldh [hSerialDone], a
;> rSB = 0
	ldh [rSB], a
;> hSerialSendPending = 0
	ldh [hSerialSendPending], a
;> hSerialRx = 0
	ldh [hSerialRx], a
;> hSerialTx = 0
	ldh [hSerialTx], a
;> hRoundResult = 0
	ldh [hRoundResult], a
;> ClearScoreData()
	call ClearScoreData
;> ClearClearedRows()
	call ClearClearedRows
;> ClearHiddenRows()
	call ClearHiddenRows
;> hBoardCopyStage = 0
	xor a
	ldh [hBoardCopyStage], a
;> ClearShadowOAM()
	call ClearShadowOAM
;>@lvl hLevel = 1
;>@two hTwoPlayer = 1
;>@ls LoadScreen(VersusGameScreen)
	ld de, VersusGameScreen
;=@lsa
	push de
;=@lvl
	ld a, $01
	ldh [hLevel], a
;=@two
	ldh [hTwoPlayer], a
;=@ls
	call LoadScreen
;>@lsa LoadScreenAt(VersusGameScreen, vBGMap1)
	pop de
	ld hl, vBGMap1
	call LoadScreenAt
;> CopyTilemap8Wide(vBGMap1 + 0x63, PauseScreenText, 10)
	ld de, PauseScreenText
	ld hl, vBGMap1 + $63
	ld c, $0a
	call CopyTilemap8Wide
;> CopyUntilFF(wObjects, FallingPieceTemplate)
	ld hl, wObjects
	ld de, FallingPieceTemplate
	call CopyUntilFF
;> CopyUntilFF(addr(wObjects) + 0x10, NextPieceTemplate)
	ld hl, wObjects + $10
	ld de, NextPieceTemplate
	call CopyUntilFF
;>@lines hLines = (hLines & 0xFF00) | 0x30              # 30 lines to clear
;>@d1 mem[vBGMap0 + 0x151] = 0
	ld hl, vBGMap0 + $151
;=@lines
	ld a, $30
	ldh [hLines], a
;=@d1
	ld [hl], $00
;> mem[vBGMap0 + 0x150] = 3
	dec l
	ld [hl], $03
;> SetFallSpeed()
	call SetFallSpeed
;> hTemp = 0
	xor a
	ldh [hTemp], a
;> if hSerialRole == SERIAL_MASTER:
	ldh a, [hSerialRole]
	cp SERIAL_MASTER
;>     icon = MasterIcon
	ld de, MasterIcon
;>     height = hMasterHeight
	ldh a, [hMasterHeight]
;> else:
	jr z, .showHeight

;>     icon = SlaveIcon
	ld de, SlaveIcon
;>     height = hSlaveHeight
	ldh a, [hSlaveHeight]

;> mem[vBGMap0 + 0xB0] = height
.showHeight
	ld hl, vBGMap0 + $B0
	ld [hl], a
;> mem[vBGMap1 + 0xB0] = height
	ld h, HIGH(vBGMap1)
	ld [hl], a
;> CopyBytesB(addr(wShadowOAM) + 0x80, icon, 16)
	ld hl, wShadowOAM + $80
	ld b, $10
	call CopyBytesB
;> hGameType = GAME_TYPE_B
	ld a, GAME_TYPE_B
	ldh [hGameType], a
;> rLCDC = 0xD3
	ld a, $d3
	ldh [rLCDC], a
;> hGameState = 0x19                                # State19_VersusSync
	ld a, $19
	ldh [hGameState], a
;> hSerialState = 1
	ld a, $01
	ldh [hSerialState], a
;> return
	ret

; Shadow OAM entries for the small face in the corner: slave (Luigi)
SlaveIcon::
	db $18, $84, $c0, $00, $18, $8c, $c0, $20, $20, $84, $c1, $00, $20, $8c, $c1, $20

; Shadow OAM entries for the small face in the corner: master (Mario)
MasterIcon::
	db $18, $84, $ae, $00, $18, $8c, $ae, $20, $20, $84, $af, $00, $20, $8c, $af, $20

;@ def State19_VersusSync()
;@ path: versus/setup
;@ Game state $19: the master sends the slave its garbage rows (rows 8-17 of
;@ wBGMap0Copy) and the piece sequence, with handshakes in between; each
;@ side shows only as much garbage as its handicap height asks for.
;@ reads: hSerialRole, hMasterHeight, wBGMap0Copy, wPieceList
;@ writes: rIE, rIF, hSerialDone, rSB, rSC, wBGMap0Copy
;@ test: skip talks to the link cable
;@ sig: 696e2e99
State19_VersusSync::
;> rIE = 0x08                                       # only the serial interrupt
	ld a, $08
	ldh [rIE], a
;> rIF = 0
	xor a
	ldh [rIF], a
;> if hSerialRole != SERIAL_MASTER: goto(VersusSyncSlave)
	ldh a, [hSerialRole]
	cp SERIAL_MASTER
	jp nz, VersusSyncSlave

;>@hs1 while True:                                  # handshake
;>     Delay()
.handshake:
	call Delay
;>     Delay()
	call Delay
;>     hSerialDone = 0
	xor a
	ldh [hSerialDone], a
;>     rSB = SERIAL_MASTER
	ld a, SERIAL_MASTER
	ldh [rSB], a
;>     rSC = 0x81                                   # start the transfer on our clock
	ld a, $81
	ldh [rSC], a

;>     while not hSerialDone: pass
.handshakeWait:
	ldh a, [hSerialDone]
	and a
	jr z, .handshakeWait

;>     if rSB == SERIAL_SLAVE: break
	ldh a, [rSB]
	cp SERIAL_SLAVE
;=@hs1
	jr nz, .handshake

;>@src src = wBGMap0Copy + 0x102                   # the 10 garbage rows (rows 8-17)
;>@rows for _ in range(10):
;=@next
	ld de, $0016
;=@rows
	ld c, $0a
;=@src
	ld hl, wBGMap0Copy + $102

;>@cols     for _ in range(10):
.sendRow:
	ld b, $0a

;>         hSerialDone = 0
.sendByte:
	xor a
	ldh [hSerialDone], a
;>         Delay()
	call Delay
;>         rSB = mem[src]; src += 1
	ld a, [hli]
	ldh [rSB], a
;>         rSC = 0x81
	ld a, $81
	ldh [rSC], a

;>         while not hSerialDone: pass
.sendWait:
	ldh a, [hSerialDone]
	and a
	jr z, .sendWait

;=@cols
	dec b
	jr nz, .sendByte

;>@next     src += 32 - 10                          # next row
	add hl, de
;=@rows
	dec c
	jr nz, .sendRow

;> if hMasterHeight != 5:                           # own board: keep only `height` levels
	ldh a, [hMasterHeight]
	cp $05
	jr z, .handshake2

;>     dst = wBGMap0Copy + 0x222                    # move the garbage down (below row 17 is hidden)
	ld hl, wBGMap0Copy + $222
;>@sh     for _ in range(5 - hMasterHeight):
	ld de, $0040

;>         dst += 0x40
.findShift:
	add hl, de
;=@sh
	inc a
	cp $05
	jr nz, .findShift

;>     src = wBGMap0Copy + 0x222
	ld de, wBGMap0Copy + $222
;>@mr     for _ in range(10):                       # 10 rows, bottom up
	ld c, $0a

;>@mb         for _ in range(10):
.moveRow:
	ld b, $0a

;>             mem[dst] = mem[src]; dst += 1
.moveByte:
	ld a, [de]
	ld [hli], a
;>             src += 1                             # (inc e: no carry within a row)
	inc e
;=@mb
	dec b
	jr nz, .moveByte

;>         dst -= 42                                # back to the start of the row above
	push de
	ld de, -42
	add hl, de
	pop de
;>         src -= 42
	push hl
	ld hl, -42
	add hl, de
	push hl
	pop de
	pop hl
;=@mr
	dec c
	jr nz, .moveRow

;>@cw     while hi(dst) != 0xC8:                    # clear what is left above, up to row 8
;=@step
	ld de, -42

;=@cb
.clearRow:
	ld b, $0a
;=@cw
	ld a, h
	cp HIGH(wBGMap0Copy)
	jr z, .handshake2

;>@cb         for _ in range(10):
;>             mem[dst] = TILE_BLANK; dst += 1
	ld a, TILE_BLANK

.clearByte:
	ld [hli], a
;=@cb
	dec b
	jr nz, .clearByte

;>@step         dst -= 42
	add hl, de
;=@cw
	jr .clearRow

;>@hs2 while True:                                  # handshake
;>     Delay()
.handshake2:
	call Delay
;>     Delay()
	call Delay
;>     hSerialDone = 0
	xor a
	ldh [hSerialDone], a
;>     rSB = SERIAL_MASTER
	ld a, SERIAL_MASTER
	ldh [rSB], a
;>     rSC = 0x81
	ld a, $81
	ldh [rSC], a

;>     while not hSerialDone: pass
.handshake2Wait:
	ldh a, [hSerialDone]
	and a
	jr z, .handshake2Wait

;>     if rSB == SERIAL_SLAVE: break
	ldh a, [rSB]
	cp SERIAL_SLAVE
;=@hs2
	jr nz, .handshake2

;>@pc for i in range(256):                          # the piece sequence
	ld hl, wPieceList
	ld b, $00

;>     hSerialDone = 0
.sendPiece:
	xor a
	ldh [hSerialDone], a
;>     piece = wPieceList[i]
	ld a, [hli]
;>     Delay()
	call Delay
;>     rSB = piece
	ldh [rSB], a
;>     rSC = 0x81
	ld a, $81
	ldh [rSC], a

;>     while not hSerialDone: pass
.sendPieceWait:
	ldh a, [hSerialDone]
	and a
	jr z, .sendPieceWait

;=@pc
	inc b
	jr nz, .sendPiece

;>@hs3 while True:                                  # final handshake
;>     Delay()
.handshake3:
	call Delay
;>     Delay()
	call Delay
;>     hSerialDone = 0
	xor a
	ldh [hSerialDone], a
;>     rSB = 0x30
	ld a, $30
	ldh [rSB], a
;>     rSC = 0x81
	ld a, $81
	ldh [rSC], a

;>     while not hSerialDone: pass
.handshake3Wait:
	ldh a, [hSerialDone]
	and a
	jr z, .handshake3Wait

;>     if rSB == 0x56: break
	ldh a, [rSB]
	cp $56
;=@hs3
	jr nz, .handshake3

;> VersusSyncDone()                                 # falls through

;@ def VersusSyncDone()
;@ path: versus/setup
;@ End of the 2-player sync: a solid row under the board, interrupts back
;@ on, the first two pieces from the shared sequence, and state $1C.
;@ reads: hSerialRole, wPieceList
;@ writes: rIE, hGameState, hBoardCopyStage, hSerialState, wObjects, hPieceListPosHi, hPieceListPos
;@ test: skip part of the link cable protocol
;@ sig: 61b80b52
VersusSyncDone::
;> FillRow18()
	call FillRow18
;> rIE = 0x09
	ld a, $09
	ldh [rIE], a
;> hGameState = 0x1C                                # State1C_VersusRoundStart
	ld a, $1c
	ldh [hGameState], a
;> hBoardCopyStage = 2                              # show the board
	ld a, $02
	ldh [hBoardCopyStage], a
;> hSerialState = 3
	ld a, $03
	ldh [hSerialState], a
;> if hSerialRole != SERIAL_MASTER:
	ldh a, [hSerialRole]
	cp SERIAL_MASTER
	jr z, .pieces

;>     rSC |= 0x80
	ld hl, rSC
	set 7, [hl]

;> wObjects[0x03] = wPieceList[0]
.pieces
	ld hl, wPieceList
	ld a, [hli]
	ld [wObjects + $03], a
;> wObjects[0x13] = wPieceList[1]
	ld a, [hli]
	ld [wObjects + $13], a
;> hPieceListPosHi = hi(addr(wPieceList))
	ld a, h
	ldh [hPieceListPosHi], a
;> hPieceListPos = 2
	ld a, l
	ldh [hPieceListPos], a
;> return
	ret


;@ def VersusSyncSlave()
;@ path: versus/setup
;@ The slave's side of State19_VersusSync: receives the garbage rows (placed
;@ lower the smaller its handicap height) and the piece sequence.
;@ reads: hSlaveHeight
;@ writes: hSerialDone, rSB, rSC, wBGMap0Copy, wPieceList
;@ test: skip talks to the link cable
;@ sig: 389ab470
VersusSyncSlave::
;>@dest dest = wBGMap0Copy + 0x242
;>@up for _ in range(hSlaveHeight):                # each height level: 2 rows higher
	ldh a, [hSlaveHeight]
	inc a
	ld b, a
;=@dest
	ld hl, wBGMap0Copy + $242
;=@step
	ld de, -64

;=@up
.findDest:
	dec b
	jr z, .handshake

;>@step     dest -= 64
	add hl, de
;=@up
	jr .findDest

;>@hs1 while True:                                  # handshake
;>     Delay()
.handshake:
	call Delay
;>     hSerialDone = 0
	xor a
	ldh [hSerialDone], a
;>     rSB = SERIAL_SLAVE
	ld a, SERIAL_SLAVE
	ldh [rSB], a
;>     rSC = 0x80                                   # on the master's clock
	ld a, $80
	ldh [rSC], a

;>     while not hSerialDone: pass
.handshakeWait:
	ldh a, [hSerialDone]
	and a
	jr z, .handshakeWait

;>     if rSB == SERIAL_MASTER: break
	ldh a, [rSB]
	cp SERIAL_MASTER
;=@hs1
	jr nz, .handshake

;>@rows for _ in range(10):                         # the 10 garbage rows
;=@next
	ld de, $0016
;=@rows
	ld c, $0a

;>@cols     for _ in range(10):
.receiveRow:
	ld b, $0a

;>         hSerialDone = 0
.receiveByte:
	xor a
	ldh [hSerialDone], a
;>         rSB = 0
	ldh [rSB], a
;>         rSC = 0x80
	ld a, $80
	ldh [rSC], a

;>         while not hSerialDone: pass
.receiveWait:
	ldh a, [hSerialDone]
	and a
	jr z, .receiveWait

;>         mem[dest] = rSB; dest += 1
	ldh a, [rSB]
	ld [hli], a
;=@cols
	dec b
	jr nz, .receiveByte

;>@next     dest += 32 - 10                         # next row
	add hl, de
;=@rows
	dec c
	jr nz, .receiveRow

;>@hs2 while True:                                  # handshake
;>     Delay()
.handshake2:
	call Delay
;>     hSerialDone = 0
	xor a
	ldh [hSerialDone], a
;>     rSB = SERIAL_SLAVE
	ld a, SERIAL_SLAVE
	ldh [rSB], a
;>     rSC = 0x80
	ld a, $80
	ldh [rSC], a

;>     while not hSerialDone: pass
.handshake2Wait:
	ldh a, [hSerialDone]
	and a
	jr z, .handshake2Wait

;>     if rSB == SERIAL_MASTER: break
	ldh a, [rSB]
	cp SERIAL_MASTER
;=@hs2
	jr nz, .handshake2

;>@pc for i in range(256):                          # the piece sequence
	ld b, $00
	ld hl, wPieceList

;>     hSerialDone = 0
.receivePiece:
	xor a
	ldh [hSerialDone], a
;>     rSB = 0
	ldh [rSB], a
;>     rSC = 0x80
	ld a, $80
	ldh [rSC], a

;>     while not hSerialDone: pass
.receivePieceWait:
	ldh a, [hSerialDone]
	and a
	jr z, .receivePieceWait

;>     wPieceList[i] = rSB
	ldh a, [rSB]
	ld [hli], a
;=@pc
	inc b
	jr nz, .receivePiece

;>@hs3 while True:                                  # final handshake
;>     Delay()
.handshake3:
	call Delay
;>     hSerialDone = 0
	xor a
	ldh [hSerialDone], a
;>     rSB = 0x56
	ld a, $56
	ldh [rSB], a
;>     rSC = 0x80
	ld a, $80
	ldh [rSC], a

;>     while not hSerialDone: pass
.handshake3Wait:
	ldh a, [hSerialDone]
	and a
	jr z, .handshake3Wait

;>     if rSB == 0x30: break
	ldh a, [rSB]
	cp $30
;=@hs3
	jr nz, .handshake3

;> goto(VersusSyncDone)
	jp VersusSyncDone


;@ def FillRow18()
;@ path: versus/setup
;@ Fills board row 18 of wBGMap0Copy (just below the visible board) with blocks.
;@ clobbers: a, b, hl
;@ sig: 8058f96b
FillRow18::
;>@lp for i in range(10):
	ld hl, wBGMap0Copy + $242
	ld a, $80
	ld b, $0a

.loop
;>     wBGMap0Copy[0x242 + i] = 0x80
	ld [hli], a
;=@lp
	dec b
	jr nz, .loop

;> return
	ret


;@ def Delay()
;@ path: lib/timing
;@ Busy-waits about 5000 cycles (1.2 ms), e.g. between serial transfers.
;@ sig: f9350234
Delay::
;> # (bc is saved and restored)
	push bc
;>@lp for _ in range(250):                          # 250 rounds of a 20-cycle loop
	ld b, $fa

.loop
;>     pass
	ld b, b
;=@lp
	dec b
	jr nz, .loop

;> return
	pop bc
	ret


;@ def RollListPiece() -> a
;@ path: versus/menu
;@ The randomizer of SpawnNextPiece, used by the 2-player master to deal the
;@ shared piece sequence; hPrevPieceRoll holds the last piece dealt.
;@ reads: hPrevPieceRoll, rDIV, hNextPieceRoll
;@ writes: hNextPieceRoll, hPrevPieceRoll
;@ test: hPrevPieceRoll = 4 * rand(0, 6)
;@ test: hNextPieceRoll = 4 * rand(0, 6)
;@ sig: 43b47b87
RollListPiece::
;> # (hl and bc are saved and restored)
	push hl
	push bc
;> current = hPrevPieceRoll & 0xFC
	ldh a, [hPrevPieceRoll]
	and $fc
	ld c, a
;>@for for attempt in range(3):
	ld h, $03

;>     n = rDIV                                    # roll = 4 * (u8(rDIV - 1) % 7):
.roll
	ldh a, [rDIV]
	ld b, a

;>     roll = 0
.wrap
	xor a

;>@cnt     while True:
;>         n = u8(n - 1)
.count
	dec b
;>@brk         if n == 0: break
	jr z, .rolled

;>         roll += 4
	inc a
	inc a
	inc a
	inc a
;>         if roll == 28:
	cp $1c
;>             roll = 0
	jr z, .wrap

;=@cnt
	jr .count

;=@brk
.rolled
	ld d, a
;>     piece = hNextPieceRoll
	ldh a, [hNextPieceRoll]
	ld e, a
;>     if attempt == 2: break
	dec h
	jr z, .accept

;>     if (piece | roll | current) & 0xFC != current: break
	or d
	or c
	and $fc
	cp c
;=@for
	jr z, .roll

;> hNextPieceRoll = roll
.accept
	ld a, d
	ldh [hNextPieceRoll], a
;> hPrevPieceRoll = piece
	ld a, e
	ldh [hPrevPieceRoll], a
;> return piece
	pop bc
	pop hl
	ret


;@ def State1C_VersusRoundStart()
;@ path: versus/setup
;@ Game state $1C: once the board refresh has drawn the board the round
;@ starts (state $1A). At refresh stage 5 the garbage row template gets its
;@ hole and the garbage indicator sprites are reset.
;@ reads: hBoardCopyStage, wPreviewHidden, wPieceList
;@ writes: rIE, hSerialState, wObjects, hVersusNextRound, hGameState, wShadowOAM, wGarbageRow, hSerialSendPending
;@ test: skip calls SyncWithPartner, which has no pseudo-code yet
;@ sig: 19106cbf
State1C_VersusRoundStart::
;> rIE = 0x01
	ld a, $01
	ldh [rIE], a
;> if hBoardCopyStage == 0:
	ldh a, [hBoardCopyStage]
	and a
	jr nz, .refreshing

;>     SyncWithPartner()                                  # (b = $44, c = $20)
	ld b, $44
	ld c, $20
	call SyncWithPartner
;>     hSerialState = 2
	ld a, $02
	ldh [hSerialState], a
;>     if wPreviewHidden:
	ld a, [wPreviewHidden]
	and a
	jr z, .draw

;>         wObjects[0x10] = 0x80
	ld a, $80
	ld [wObjects + $10], a

;>     DrawObject0()
.draw
	call DrawObject0
;>     DrawObject1()
	call DrawObject1
;>     PlaySelectedMusic()
	call PlaySelectedMusic
;>     hVersusNextRound = 0
	xor a
	ldh [hVersusNextRound], a
;>     hGameState = 0x1A
	ld a, $1a
	ldh [hGameState], a
;>     return
	ret

;> if hBoardCopyStage != 5: return
.refreshing
	cp $05
	ret nz

;>@spr for i in range(18):                          # garbage indicator sprites
	ld hl, wShadowOAM + $30
	ld b, $12

;>     wShadowOAM[0x30 + 4 * i] = 0xF0
.sprites
	ld [hl], $f0
	inc hl
;>     wShadowOAM[0x31 + 4 * i] = 0x10
	ld [hl], $10
	inc hl
;>     wShadowOAM[0x32 + 4 * i] = 0xB6
	ld [hl], $b6
	inc hl
;>     wShadowOAM[0x33 + 4 * i] = 0x80
	ld [hl], $80
	inc hl
;=@spr
	dec b
	jr nz, .sprites

;> n = wPieceList[0xFF]                             # the hole goes at u8(n - 1) % 10
	ld a, [wPieceList + $FF]

;> i = 0
.findHole
	ld b, $0a
	ld hl, wGarbageRow

;>@step while True:
;>     n = u8(n - 1)
.step
	dec a
;>     if n == 0: break
	jr z, .hole

;>     i = (i + 1) % 10
	inc l
	dec b
;=@step
	jr nz, .step

	jr .findHole

;> wGarbageRow[i] = TILE_BLANK                      # the hole
.hole
	ld [hl], TILE_BLANK
;> hSerialSendPending = 3
	ld a, $03
	ldh [hSerialSendPending], a
;> return
	ret


;@ def State1A_VersusPlaying()
;@ path: versus/play
;@ Game state $1A: one frame of a 2-player round - the normal game logic,
;@ then the exchange with the other Game Boy. Reaching the line goal ($77 to
;@ the opponent) or topping out ($AA) ends the round.
;@ reads: hVersusGoalReached, hGameState, hSerialRole
;@ writes: rIE, wShadowOAM, hSerialTx, hVersusTx, hRoundResult, hGameState, hTimer2, hLineClearKind, hGarbageIncoming, hGarbagePending, hGarbageAdded, hSerialSendPending
;@ test: skip talks to the link cable
;@ sig: e12d136b
State1A_VersusPlaying::
;> rIE = 0x01
	ld a, $01
	ldh [rIE], a
;> wShadowOAM[0x9C] = 0
	ld hl, wShadowOAM + $9C
	xor a
	ld [hli], a
;> wShadowOAM[0x9D] = 0x50
	ld [hl], $50
;> wShadowOAM[0x9E] = 0x27
	inc l
	ld [hl], $27
;> wShadowOAM[0x9F] = 0
	inc l
	ld [hl], $00
;> HandlePause()
	call HandlePause
;> UpdateLinkPause()
	call UpdateLinkPause
;> HandlePieceInput()
	call HandlePieceInput
;> UpdateFall()
	call UpdateFall
;> CheckLines()
	call CheckLines
;> LockPiece()
	call LockPiece
;> CollapseClearedRows()
	call CollapseClearedRows
;> CheckStackHeight()
	call CheckStackHeight
;> if hVersusGoalReached:                           # we cleared our lines: we win
	ldh a, [hVersusGoalReached]
	and a
	jr z, .checkTopOut

;>     hSerialTx = 0x77
	ld a, $77
	ldh [hSerialTx], a
;>     hVersusTx = 0x77
	ldh [hVersusTx], a
;>     hRoundResult = 0xAA
	ld a, $aa
	ldh [hRoundResult], a
;>     hGameState = 0x1B
	ld a, $1b
	ldh [hGameState], a
;>     hTimer2 = 5
	ld a, $05
	ldh [hTimer2], a
;>     finished = True
	jr .finished

;> elif hGameState == 0x01:                         # we topped out: we lose
.checkTopOut
	ldh a, [hGameState]
	cp $01
;=@nf
	jr nz, .exchange

;>     hSerialTx = 0xAA
	ld a, $aa
	ldh [hSerialTx], a
;>     hVersusTx = 0xAA
	ldh [hVersusTx], a
;>     hRoundResult = 0x77
;>     finished = True
	ld a, $77
	ldh [hRoundResult], a

;>@nf else:
;>     finished = False
;> if finished:
;>     hLineClearKind = 0
.finished
	xor a
	ldh [hLineClearKind], a
;>     hGarbageIncoming = 0
	ldh [hGarbageIncoming], a
;>     hGarbagePending = 0
	ldh [hGarbagePending], a
;>     hGarbageAdded = 0
	ldh [hGarbageAdded], a
;>     if hSerialRole == SERIAL_MASTER:
	ldh a, [hSerialRole]
	cp SERIAL_MASTER
	jr nz, .exchange

;>         hSerialSendPending = SERIAL_MASTER       # (non-zero)
	ldh [hSerialSendPending], a

;> VersusExchange()
.exchange
	call VersusExchange
;> ReceiveGarbage()
	call ReceiveGarbage
;> return
	ret


;@ def CheckStackHeight()
;@ path: versus/play
;@ Measures how high our stack is (rows from the bottom up to the highest
;@ block) for the opponent's display, and switches to the danger music at 12
;@ rows or more (back to the chosen music below that).
;@ reads: wBGMap0Copy, wCurrentSong, wWaveSFXRequest
;@ writes: hVersusTx, wMusicRequest
;@ test: for r in range(18): mem[0xC802 + 32 * r + rand(0, 9)] = rng.choice([0x2F, 0x2F, 0x80])
;@ test: wCurrentSong = rng.choice([0, 8])
;@ test: wWaveSFXRequest = rng.choice([0, 2])
;@ test: hMusicType = rand(0x1C, 0x1F)
;@ sig: 59204d3a
CheckStackHeight::
;> row = wBGMap0Copy + 2                            # top row of the well
	ld de, $0020
	ld hl, wBGMap0Copy + $002
;> height = 18
	ld a, TILE_BLANK
	ld c, $12

;>@row while height:
;>@cell     for col in range(10):
.row
	ld b, $0a
	push hl

;>         if mem[row + col] != TILE_BLANK: break
.cell
	cp [hl]
	jr nz, .found

;=@cell
	inc hl
	dec b
	jr nz, .cell

;>     else:
;>         row += 32
	pop hl
	add hl, de
;>         height -= 1
	dec c
;=@row
	jr nz, .row

;>         continue
;>     break
;> hVersusTx = height
	push hl

.found
	pop hl
	ld a, c
	ldh [hVersusTx], a
;> danger = height >= 12
	cp $0c
;> song = wCurrentSong
	ld a, [wCurrentSong]
;> if danger:
	jr nc, .danger

;>@d1     if song == 8: return
;>@d2     if wWaveSFXRequest == 2: return
;>@d3     wMusicRequest = 8
;>@d4     return
;> if song != 8: return
	cp $08
	ret nz

;> PlaySelectedMusic()
	call PlaySelectedMusic
;> return
	ret

;=@d1
.danger
	cp $08
	ret z

;=@d2
	ld a, [wWaveSFXRequest]
	cp $02
	ret z

;=@d3
	ld a, $08
	ld [wMusicRequest], a
;=@d4
	ret

;=@VersusExchange.slave
; part of VersusExchange: the opponent paused ($94)
VersusOpponentPaused:
	ldh a, [hSerialRole]
	cp SERIAL_MASTER
	jr z, VersusExchange.prepareTx

;=@VersusExchange.p1
	ld a, $01
	ld [wSoundPause], a
;=@VersusExchange.p2
	ldh [hPaused], a
;=@VersusExchange.p3
	ldh a, [hSerialTx]
	ldh [hPausedSerialTx], a
;=@VersusExchange.p4
	xor a
	ldh [hPausedSerialRx], a
;=@VersusExchange.p5
	ldh [hSerialTx], a
;=@VersusExchange.p6
	call DrawPauseText
;=@VersusExchange.p7
	ret


;@ def VersusExchange()
;@ path: versus/play
;@ Handles the byte from the other Game Boy and prepares ours. Received:
;@ $AA (it lost) / $77 (it won), $94 (paused), 1-18 (its stack height, shown
;@ as a column of marker sprites), $80 + n (it cleared lines: n rows of
;@ garbage for us). Sent: hVersusTx, or $80 + kind after our own line clear.
;@ reads: hSerialDone, hSerialRx, hRoundResult, hLineClearKind, hSerialRole, hVersusTx
;@ writes: hSerialDone, wShadowOAM, hRoundResult, hGameState, hTimer2, hRoundTie, hGarbageIncoming, hVersusTx, hLineClearKind, hSerialRx, hSerialTx, hSerialSendPending, hPaused, hPausedSerialRx, hPausedSerialTx, wSoundPause
;@ test: skip talks to the link cable
;@ sig: 01d92ed8
VersusExchange::
;> if not hSerialDone: return
	ldh a, [hSerialDone]
	and a
	ret z

;> p = addr(wShadowOAM) + 0x30                     # marker sprites: shadow OAM entries 12-29
	ld hl, wShadowOAM + $30
	ld de, $0004
;> hSerialDone = 0
	xor a
	ldh [hSerialDone], a
;> rx = hSerialRx
;> shown = None                                     # opponent's stack height to show
;> send_kind = True
	ldh a, [hSerialRx]
;> if rx == 0xAA:                                   # the opponent topped out
	cp $aa
	jr z, .opponentLost

;>@lost     if hRoundResult == 0x77:
;>@tie         hRoundTie = 1
;>     else:
;>@lr         hRoundResult = 0xAA
;>@lg         hGameState = 0x1B
;>@lt         hTimer2 = 5
;>@lm         shown = 18
;> elif rx == 0x77:                                 # the opponent reached its goal
	cp $77
	jr z, .opponentWon

;>@won     if hRoundResult == 0xAA:
;>         hRoundTie = 1                            # (the shared .tie code above)
;>     else:
;>@wr         hRoundResult = 0x77
;>@wg         hGameState = 0x01
;> elif rx == 0x94:                                 # the opponent paused
	cp $94
	jr z, VersusOpponentPaused

;>@slave     if hSerialRole != SERIAL_MASTER:             # the slave pauses too (VersusOpponentPaused)
;>@p1         wSoundPause = 1
;>@p2         hPaused = 1
;>@p3         hPausedSerialTx = hSerialTx
;>@p4         hPausedSerialRx = 0
;>@p5         hSerialTx = 0
;>@p6         DrawPauseText()
;>@p7         return
;>@zero elif rx == 0:
	ld b, a
	and a
	jr z, .noMarkers

;>@none     shown = 0
;> elif rx & 0x80:                                  # it cleared lines: garbage for us
	bit 7, a
	jr nz, .garbage

;>@g1     if rx & 0x7F < 5:
;>@g2         hGarbageIncoming = rx & 0x7F
;>@g3         send_kind = False
;> elif rx < 0x13:                                  # its stack height
	cp $13
	jr nc, .prepareTx

;>     shown = rx                                   # (b = rx; c = 19 - rx)
	ld a, $12
	sub b
	ld c, a
	inc c

;> if shown is not None:                            # from y = $98 up, the rest hidden
;>     y = 0x98
.showMarkers:
	ld a, $98

;>@show     for i in range(shown):
;>         mem[p] = y
.markerLoop:
	ld [hl], a
;>         p += 4
	add hl, de
;>         y -= 8
	sub $08
;=@show
	dec b
	jr nz, .markerLoop

;>@hide     for i in range(18 - shown):
.hideMarkers:
	ld a, $f0

.hideLoop:
	dec c
	jr z, .prepareTx

;>         mem[p] = 0xF0
	ld [hl], a
;>         p += 4
	add hl, de
;=@hide
	jr .hideLoop

;> if send_kind and hLineClearKind:                 # tell the opponent about our line clear
.prepareTx:
	ldh a, [hLineClearKind]
	and a
	jr z, .send

;>     hVersusTx = hLineClearKind | 0x80
	or $80
	ldh [hVersusTx], a
;>     hLineClearKind = 0
	xor a
	ldh [hLineClearKind], a

;> hSerialRx = 0xFF
.send:
	ld a, $ff
	ldh [hSerialRx], a
;> if hSerialRole == SERIAL_MASTER:
	ldh a, [hSerialRole]
	cp SERIAL_MASTER
	ldh a, [hVersusTx]
	jr nz, .slaveSend

;>     hSerialTx = hVersusTx
	ldh [hSerialTx], a
;>     hSerialSendPending = 1
	ld a, $01
	ldh [hSerialSendPending], a
;>     return
	ret

;> hSerialTx = hVersusTx
.slaveSend:
	ldh [hSerialTx], a
;> return
	ret

;=@won
.opponentWon:
	ldh a, [hRoundResult]
	cp $aa
	jr z, .tie

;=@wr
	ld a, $77
	ldh [hRoundResult], a
;=@wg
	ld a, $01
	ldh [hGameState], a
	jr .prepareTx

;=@none
.noMarkers:
	ld c, $13
	jr .hideMarkers

;=@lost
.opponentLost:
	ldh a, [hRoundResult]
	cp $77
	jr z, .tie

;=@lr
	ld a, $aa
	ldh [hRoundResult], a
;=@lg
	ld a, $1b
	ldh [hGameState], a
;=@lt
	ld a, $05
	ldh [hTimer2], a
;=@lm
	ld c, $01
	ld b, $12
	jr .showMarkers

;=@tie
.tie:
	ld a, $01
	ldh [hRoundTie], a
	jr .prepareTx

;=@g1
.garbage:
	and $7f
	cp $05
	jr nc, .prepareTx

;=@g2
	ldh [hGarbageIncoming], a
;=@g3
	jr .send

;@ def ReceiveGarbage()
;@ path: versus/play
;@ Garbage from the opponent waits in hGarbagePending until the next piece
;@ spawns (which sets bit 7); then the board moves up by that many rows and
;@ copies of wGarbageRow fill the bottom.
;@ reads: hGarbagePending, hGarbageIncoming, wGarbageRow
;@ writes: hGarbagePending, hGarbageIncoming, hBoardCopyStage, hGarbageAdded
;@ test: hGarbagePending = rng.choice([0, 0, 1, 0x81, 0x82, 0x84])
;@ test: hGarbageIncoming = rng.choice([0, 1, 2, 4])
;@ sig: 4cbde536
ReceiveGarbage::
;> if hGarbagePending:
	ldh a, [hGarbagePending]
	and a
	jr z, .queue

;>     if not hGarbagePending & 0x80: return        # wait for the next piece
	bit 7, a
	ret z

;>     rows = hGarbagePending & 0x07
	and $07
;> else:
	jr .add

;>     if not hGarbageIncoming: return
.queue
	ldh a, [hGarbageIncoming]
	and a
	ret z

;>     hGarbagePending = hGarbageIncoming
	ldh [hGarbagePending], a
;>     hGarbageIncoming = 0
	xor a
	ldh [hGarbageIncoming], a
;>     return
	ret

;> dest = wBGMap0Copy + 0x22                        # board rows 1-17 move up by `rows`
.add
	ld c, a
	push bc
	ld hl, wBGMap0Copy + $022
	ld de, -32

;>@top for _ in range(rows):
;>     dest -= 32
.findTop
	add hl, de
;=@top
	dec c
	jr nz, .findTop

;> src = wBGMap0Copy + 0x22
	ld de, wBGMap0Copy + $022
;>@move for row in range(17):
	ld c, $11

;>@copy     for i in range(10):
.moveUp
	ld b, $0a

;>         mem[dest + i] = mem[src + i]
.copyRow
	ld a, [de]
	ld [hli], a
	inc e
;=@copy
	dec b
	jr nz, .copyRow

;>     dest += 32
	push de
	ld de, $0016
	add hl, de
	pop de
;>     src += 32
	push hl
	ld hl, $0016
	add hl, de
	push hl
	pop de
	pop hl
;=@move
	dec c
	jr nz, .moveUp

;>@gar for _ in range(rows):                        # garbage at the bottom
	pop bc

;>@grow     for i in range(10):
.garbage
	ld de, wGarbageRow
	ld b, $0a

;>         mem[dest + i] = wGarbageRow[i]
.garbageRow
	ld a, [de]
	ld [hli], a
	inc de
;=@grow
	dec b
	jr nz, .garbageRow

;>     dest += 32
	push de
	ld de, $0016
	add hl, de
	pop de
;=@gar
	dec c
	jr nz, .garbage

;> hBoardCopyStage = 2
	ld a, $02
	ldh [hBoardCopyStage], a
;> hGarbageAdded = 2
	ldh [hGarbageAdded], a
;> hGarbagePending = 0
	xor a
	ldh [hGarbagePending], a
;> return
	ret


;@ def State1B_VersusRoundOver()
;@ path: versus/play
;@ Game state $1B: after a short wait, settles the round: a tie if both
;@ finished at once, then (once both Game Boys are in step) the win or loss
;@ screen.
;@ reads: hTimer1, hRoundResult, hSerialRx
;@ writes: rIE, hSerialState, hRoundTie, hBoardCopyStage, hGameState, hTimer1, hDemoCountdown
;@ test: skip talks to the link cable
;@ sig: 9582463a
State1B_VersusRoundOver::
;> if hTimer1: return
	ldh a, [hTimer1]
	and a
	ret nz

;> rIE = 0x01
	ld a, $01
	ldh [rIE], a
;> hSerialState = 3
	ld a, $03
	ldh [hSerialState], a
;> if hRoundResult == 0x77:                         # both finished at once: a tie
	ldh a, [hRoundResult]
	cp $77
	jr nz, .wonSide

;>     if hSerialRx == 0xAA:
	ldh a, [hSerialRx]
	cp $aa
	jr nz, .sync

;>         hRoundTie = 1
.tie
	ld a, $01
	ldh [hRoundTie], a
	jr .sync

;> elif hRoundResult == 0xAA:
.wonSide
	cp $aa
	jr nz, .sync

;>     if hSerialRx == 0x77:
	ldh a, [hSerialRx]
	cp $77
	jr z, .tie

;>@tie2         hRoundTie = 1                            # (the .tie code above)
;> SyncWithPartner(0x34, 0x43)
.sync
	ld b, $34
	ld c, $43
	call SyncWithPartner
;> hBoardCopyStage = 0
	xor a
	ldh [hBoardCopyStage], a
;> won = hRoundResult == 0xAA
	ldh a, [hRoundResult]
	cp $aa
;> state = 0x1E                                     # lost
	ld a, $1e
;> if won:
	jr nz, .setState

;>     state = 0x1D                                 # won
	ld a, $1d

;> hGameState = state
.setState
	ldh [hGameState], a
;> hTimer1 = 0x28
	ld a, $28
	ldh [hTimer1], a
;> hDemoCountdown = 0x1D                            # (borrowed: animation countdown)
	ld a, $1d
	ldh [hDemoCountdown], a
;> return
	ret


;@ def State1D_VersusWon()
;@ path: versus/results
;@ Game state $1D: this player won the round - count it (not for a tie),
;@ show the tally screen with our character cheering.
;@ reads: hTimer1, hRoundTie, hSerialRole, hVersusWins, hDemoCountdown, hJoyPressed
;@ writes: hVersusWins, hTimer1, wObjects, hGameState, wMusicRequest, hSerialSendPending, hSerialTx
;@ test: skip switches the LCD off
;@ sig: 53e59c06
State1D_VersusWon::
;> if hTimer1: return
	ldh a, [hTimer1]
	and a
	ret nz

;> if not hRoundTie:
	ldh a, [hRoundTie]
	and a
	jr nz, .tally

;>     hVersusWins += 1
	ldh a, [hVersusWins]
	inc a
	ldh [hVersusWins], a

;> ShowVersusTally()
.tally
	call ShowVersusTally
;> objects = VersusWinObjectsMaster
	ld de, VersusWinObjectsMaster
;> if hSerialRole != SERIAL_MASTER:
	ldh a, [hSerialRole]
	cp SERIAL_MASTER
	jr z, .objects

;>     objects = VersusWinObjectsSlave
	ld de, VersusWinObjectsSlave

;> SetupObjects(wObjects, objects, 3)
.objects
	ld hl, wObjects
	ld c, $03
	call SetupObjects
;> hTimer1 = 0x19
	ld a, $19
	ldh [hTimer1], a
;> if hRoundTie:
	ldh a, [hRoundTie]
	and a
	jr z, .draw

;>     wObjects[0x20] = 0x80
	ld hl, wObjects + $20
	ld [hl], $80

;> DrawObjectsAt0(3)
.draw
	ld a, $03
	call DrawObjectsAt0
;> hGameState = 0x20
	ld a, $20
	ldh [hGameState], a
;> wMusicRequest = 0x09                             # round won
	ld a, $09
	ld [wMusicRequest], a
;> if hVersusWins != 5: return
	ldh a, [hVersusWins]
	cp $05
	ret nz

;> wMusicRequest = 0x11                             # match won
	ld a, $11
	ld [wMusicRequest], a
;> return
	ret

;=@State20_VersusWonWait.m1
; part of State20_VersusWonWait: the master decides when to go on
VersusWonMasterGo:
	ldh a, [hVersusWins]
	cp $05
	jr nz, .round

;=@State20_VersusWonWait.m2
	ldh a, [hDemoCountdown]
	and a
	jr z, .go

	jr State20_VersusWonWait.animate

;=@State20_VersusWonWait.m4
.round:
	ldh a, [hJoyPressed]
	bit 3, a
	jr z, State20_VersusWonWait.animate

;=@State20_VersusWonWait.m6
.go:
	ld a, $60
	ldh [hSerialTx], a
;=@State20_VersusWonWait.m7
	ldh [hSerialSendPending], a
	jr State20_VersusWonWait.next

;@ def State20_VersusWonWait()
;@ path: versus/results
;@ Game state $20: the winner's animation. The master continues with Start
;@ (after a won match: automatically) by sending $60; then state $1F.
;@ Note: the `jr z` after reading hSerialDone tests stale flags (from the
;@ `add a` in JumpTable), so the transfer check never skips anything.
;@ reads: hSerialRole, hSerialRx, hVersusWins, hDemoCountdown, hJoyPressed
;@ writes: rIE, hSerialTx, hSerialSendPending, hGameState, hSerialDone
;@ test: skip talks to the link cable
;@ sig: f31c57dd
State20_VersusWonWait::
;> rIE = 0x01
	ld a, $01
	ldh [rIE], a
;> # (reads hSerialDone, but the jr z tests stale flags: never taken)
	ldh a, [hSerialDone]
	jr z, .animate

;> if hSerialRole != SERIAL_MASTER:
	ldh a, [hSerialRole]
	cp SERIAL_MASTER
	jr z, VersusWonMasterGo

;>     go = hSerialRx == 0x60
	ldh a, [hSerialRx]
	cp $60
	jr z, .next

;> else:                                            # the master decides (VersusWonMasterGo)
;>@m1     if hVersusWins == 5:
;>@m2         go = hDemoCountdown == 0
;>@m3     else:
;>@m4         go = bool(hJoyPressed & BTN_START)
;>@m5     if go:
;>@m6         hSerialTx = 0x60
;>@m7         hSerialSendPending = 0x60
;>@go if go:
;>@n1     hGameState = 0x1F
;>@n2     hSerialDone = 0x1F
;>@n3     return
;> AnimateVersusWin()
.animate:
	call AnimateVersusWin
;> DrawObjectsAt0(3)
	ld a, $03
	call DrawObjectsAt0
;> return
	ret

;=@n1
.next:
	ld a, $1f
	ldh [hGameState], a
;=@n2
	ldh [hSerialDone], a
;=@n3
	ret


;@ def AnimateVersusWin()
;@ path: versus/results
;@ The winner cheers (every 25 frames); after a won match a little extra
;@ scene plays, otherwise the third object blinks every 15 frames.
;@ reads: hTimer1, hVersusWins, hDemoCountdown, hTimer2, wObjects
;@ writes: hDemoCountdown, hTimer1, wObjects, wSFXRequest, hTimer2
;@ test: hTimer1 = rng.choice([0, 0, 5])
;@ test: hTimer2 = rng.choice([0, 3])
;@ test: hDemoCountdown = rand(1, 12)
;@ test: hSerialRole = rng.choice([SERIAL_MASTER, SERIAL_SLAVE])
;@ test: mem[0xC201] = rng.choice([0x30, 0x60, 0x50, 0x58, 0x61, 0x69, 0x72, 0x75])
;@ test: mem[0xC211] = rng.choice([0x60, 0x68, 0x61, 0x72])
;@ test: mem[0xC221] = rng.choice([0x60, 0x69, 0x72, 0x75])
;@ test: hVersusWins = rng.choice([1, 5, 5])
;@ sig: aec37e37
AnimateVersusWin::
;> if not hTimer1:
	ldh a, [hTimer1]
	and a
	jr nz, .scene

;>     hDemoCountdown -= 1
	ld hl, hDemoCountdown
	dec [hl]
;>     hTimer1 = 25
	ld a, $19
	ldh [hTimer1], a
;>     HideNextRoundPrompt()
	call HideNextRoundPrompt
;>     y = wObjects[1] ^ 0x30                       # hop
	ld hl, wObjects + $01
	ld a, [hl]
	xor $30
;>     wObjects[1] = y
	ld [hli], a
;>     if y == 0x60: ShowNextRoundPrompt()
	cp $60
	call z, ShowNextRoundPrompt
;>     frame = wObjects[3] ^ 1
	inc l
	push af
	ld a, [hl]
	xor $01
;>     wObjects[3] = frame
	ld [hl], a
;>     wObjects[0x13] = frame
	ld l, $13
	ld [hld], a
;>     wObjects[0x11] = y
	pop af
	dec l
	ld [hl], a

;> if hVersusWins == 5:                             # match won: a little scene
.scene
	ldh a, [hVersusWins]
	cp $05
	jr nz, .blink

;>     t = hDemoCountdown
	ldh a, [hDemoCountdown]
	ld hl, wObjects + $21
;>     if t == 6:
	cp $06
	jr z, .hide

;>@hide         wObjects[0x20] = 0x80
;>@hret         return
;>     if t < 8:
	cp $08
	jr nc, .blink

;>         if wObjects[0x21] >= 0x72:
	ld a, [hl]
	cp $72
	jr nc, .land

;>@l1             wObjects[0x21] = 0x69
;>@l2             wObjects[0x23] = 0x57
;>@l3             wSFXRequest = 6
;>@l4             return
;>         if wObjects[0x21] == 0x69: return
	cp $69
	ret z

;>         wObjects[0x21] += 2
	inc [hl]
	inc [hl]
;>         return
	ret

;=@l1
.land
	ld [hl], $69
;=@l2
	inc l
	inc l
	ld [hl], $57
;=@l3
	ld a, $06
	ld [wSFXRequest], a
;=@l4
	ret

;=@hide
.hide
	dec l
	ld [hl], $80
;=@hret
	ret

;> if hTimer2: return                               # the third object blinks every 15 frames
.blink
	ldh a, [hTimer2]
	and a
	ret nz

;> hTimer2 = 15
	ld a, $0f
	ldh [hTimer2], a
;> wObjects[0x23] ^= 1
	ld hl, wObjects + $23
	ld a, [hl]
	xor $01
	ld [hl], a
;> return
	ret


;@ def State1E_VersusLost()
;@ path: versus/results
;@ Game state $1E: this player lost the round - count it (not for a tie),
;@ show the tally screen with our character sad.
;@ reads: hTimer1, hRoundTie, hSerialRole, hVersusLosses, hDemoCountdown, hJoyPressed
;@ writes: hVersusLosses, hTimer1, wObjects, hGameState, wMusicRequest, hSerialSendPending, hSerialTx
;@ test: skip switches the LCD off
;@ sig: 7c53870a
State1E_VersusLost::
;> if hTimer1: return
	ldh a, [hTimer1]
	and a
	ret nz

;> if not hRoundTie:
	ldh a, [hRoundTie]
	and a
	jr nz, .tally

;>     hVersusLosses += 1
	ldh a, [hVersusLosses]
	inc a
	ldh [hVersusLosses], a

;> ShowVersusTally()
.tally
	call ShowVersusTally
;> objects = VersusLoseObjectsMaster
	ld de, VersusLoseObjectsMaster
;> if hSerialRole != SERIAL_MASTER:
	ldh a, [hSerialRole]
	cp SERIAL_MASTER
	jr z, .objects

;>     objects = VersusLoseObjectsSlave
	ld de, VersusLoseObjectsSlave

;> SetupObjects(wObjects, objects, 2)
.objects
	ld hl, wObjects
	ld c, $02
	call SetupObjects
;> hTimer1 = 0x19
	ld a, $19
	ldh [hTimer1], a
;> if hRoundTie:
	ldh a, [hRoundTie]
	and a
	jr z, .draw

;>     wObjects[0x10] = 0x80
	ld hl, wObjects + $10
	ld [hl], $80

;> DrawObjectsAt0(2)
.draw
	ld a, $02
	call DrawObjectsAt0
;> hGameState = 0x21
	ld a, $21
	ldh [hGameState], a
;> wMusicRequest = 0x09
	ld a, $09
	ld [wMusicRequest], a
;> if hVersusLosses != 5: return
	ldh a, [hVersusLosses]
	cp $05
	ret nz

;> wMusicRequest = 0x11                             # match lost
	ld a, $11
	ld [wMusicRequest], a
;> return
	ret

;=@State21_VersusLostWait.m1
; part of State21_VersusLostWait: the master decides when to go on
VersusLostMasterGo:
	ldh a, [hVersusLosses]
	cp $05
	jr nz, .round

;=@State21_VersusLostWait.m2
	ldh a, [hDemoCountdown]
	and a
	jr z, .go

	jr State21_VersusLostWait.animate

;=@State21_VersusLostWait.m4
.round:
	ldh a, [hJoyPressed]
	bit 3, a
	jr z, State21_VersusLostWait.animate

;=@State21_VersusLostWait.m6
.go:
	ld a, $60
	ldh [hSerialTx], a
;=@State21_VersusLostWait.m7
	ldh [hSerialSendPending], a
	jr State21_VersusLostWait.next

;@ def State21_VersusLostWait()
;@ path: versus/results
;@ Game state $21: like State20_VersusWonWait, for the loser.
;@ reads: hSerialRole, hSerialRx, hVersusLosses, hDemoCountdown, hJoyPressed
;@ writes: rIE, hSerialTx, hSerialSendPending, hGameState, hSerialDone
;@ test: skip talks to the link cable
;@ sig: 41c7cb5f
State21_VersusLostWait::
;> rIE = 0x01
	ld a, $01
	ldh [rIE], a
;> # (reads hSerialDone, but the jr z tests stale flags: never taken)
	ldh a, [hSerialDone]
	jr z, .animate

;> if hSerialRole != SERIAL_MASTER:
	ldh a, [hSerialRole]
	cp SERIAL_MASTER
	jr z, VersusLostMasterGo

;>     go = hSerialRx == 0x60
	ldh a, [hSerialRx]
	cp $60
	jr z, .next

;> else:                                            # the master decides (VersusLostMasterGo)
;>@m1     if hVersusLosses == 5:
;>@m2         go = hDemoCountdown == 0
;>@m3     else:
;>@m4         go = bool(hJoyPressed & BTN_START)
;>@m5     if go:
;>@m6         hSerialTx = 0x60
;>@m7         hSerialSendPending = 0x60
;>@go if go:
;>@n1     hGameState = 0x1F
;>@n2     hSerialDone = 0x1F
;>@n3     return
;> AnimateVersusLoss()
.animate:
	call AnimateVersusLoss
;> DrawObjectsAt0(2)
	ld a, $02
	call DrawObjectsAt0
;> return
	ret

;=@n1
.next:
	ld a, $1f
	ldh [hGameState], a
;=@n2
	ldh [hSerialDone], a
;=@n3
	ret


;@ def AnimateVersusLoss()
;@ path: versus/results
;@ The loser's animation (every 25 frames); after a lost match a little
;@ scene, otherwise the first object blinks every 15 frames.
;@ reads: hTimer1, hVersusLosses, hDemoCountdown, hTimer2, wObjects
;@ writes: hDemoCountdown, hTimer1, wObjects, wSFXRequest, hTimer2
;@ test: hTimer1 = rng.choice([0, 0, 5])
;@ test: hTimer2 = rng.choice([0, 3])
;@ test: hDemoCountdown = rand(1, 12)
;@ test: hSerialRole = rng.choice([SERIAL_MASTER, SERIAL_SLAVE])
;@ test: mem[0xC201] = rng.choice([0x30, 0x60, 0x50, 0x58, 0x61, 0x69, 0x72, 0x75])
;@ test: mem[0xC211] = rng.choice([0x60, 0x68, 0x61, 0x72])
;@ test: mem[0xC221] = rng.choice([0x60, 0x69, 0x72, 0x75])
;@ test: hVersusLosses = rng.choice([1, 5, 5])
;@ sig: 9dbee478
AnimateVersusLoss::
;> if not hTimer1:
	ldh a, [hTimer1]
	and a
	jr nz, .scene

;>     hDemoCountdown -= 1
	ld hl, hDemoCountdown
	dec [hl]
;>     hTimer1 = 25
	ld a, $19
	ldh [hTimer1], a
;>     HideNextRoundPrompt()
	call HideNextRoundPrompt
;>     y = wObjects[0x11] ^ 0x08
	ld hl, wObjects + $11
	ld a, [hl]
	xor $08
;>     wObjects[0x11] = y
	ld [hli], a
;>     if y == 0x68: ShowNextRoundPrompt()
	cp $68
	call z, ShowNextRoundPrompt
;>     wObjects[0x13] ^= 1
	inc l
	ld a, [hl]
	xor $01
	ld [hl], a

;> if hVersusLosses == 5:                           # match lost: a little scene
.scene
	ldh a, [hVersusLosses]
	cp $05
	jr nz, .blink

;>     t = hDemoCountdown
	ldh a, [hDemoCountdown]
	ld hl, wObjects + $01
;>     if t == 5:
	cp $05
	jr z, .hide

;>@hide         wObjects[0] = 0x80
;>@hret         return
;>     if t == 6:
	cp $06
	jr z, .fall

;>@f1         wObjects[0] = 0
;>@f2         wObjects[1] = 0x61
;>@f3         wObjects[3] = 0x56
;>@f4         wSFXRequest = 6
;>@f5         return
;>     if t < 8:
	cp $08
	jr nc, .blink

;>         if wObjects[1] >= 0x72:
	ld a, [hl]
	cp $72
	jr nc, .hide

;>@h2             wObjects[0] = 0x80                # (the shared .hide code above)
;>@h3             return
;>         if wObjects[1] == 0x61: return
	cp $61
	ret z

;>         wObjects[1] += 4
	inc [hl]
	inc [hl]
	inc [hl]
	inc [hl]
;>         return
	ret

;=@f1
.fall
	dec l
	ld [hl], $00
;=@f2
	inc l
	ld [hl], $61
;=@f3
	inc l
	inc l
	ld [hl], $56
;=@f4
	ld a, $06
	ld [wSFXRequest], a
;=@f5
	ret

;=@hide
.hide
	dec l
	ld [hl], $80
;=@hret
	ret

;> if hTimer2: return                               # first object blinks every 15 frames
.blink
	ldh a, [hTimer2]
	and a
	ret nz

;> hTimer2 = 15
	ld a, $0f
	ldh [hTimer2], a
;> wObjects[3] ^= 1
	ld hl, wObjects + $03
	ld a, [hl]
	xor $01
	ld [hl], a
;> return
	ret


;@ def ShowNextRoundPrompt()
;@ path: versus/results
;@ On the master, while the match goes on: shows the 9-sprite prompt to
;@ start the next round.
;@ reads: hVersusWins, hVersusLosses, hSerialRole
;@ writes: wShadowOAM
;@ test: hVersusWins = rng.choice([0, 5])
;@ test: hVersusLosses = rng.choice([0, 5])
;@ test: hSerialRole = rng.choice([SERIAL_MASTER, SERIAL_SLAVE])
;@ sig: 47ce2a20
ShowNextRoundPrompt::
;> # (keeps af and hl)
	push af
	push hl
;> if hVersusWins == 5: return
	ldh a, [hVersusWins]
	cp $05
	jr z, .done

;> if hVersusLosses == 5: return
	ldh a, [hVersusLosses]
	cp $05
	jr z, .done

;> if hSerialRole != SERIAL_MASTER: return
	ldh a, [hSerialRole]
	cp SERIAL_MASTER
	jr nz, .done

;>@copy for i in range(36):
	ld hl, wShadowOAM + $60
	ld b, $24
	ld de, NextRoundPrompt

;>     wShadowOAM[0x60 + i] = mem[NextRoundPrompt + i]
.copy
	ld a, [de]
	ld [hli], a
	inc de
;=@copy
	dec b
	jr nz, .copy

;> return
.done
	pop hl
	pop af
	ret

; 9 shadow OAM entries: the master's prompt to start the next round
NextRoundPrompt::
	db $42, $30, $0d, $00, $42, $38, $b2, $00, $42, $40, $0e, $00, $42, $48, $1c, $00
	db $42, $58, $0e, $00, $42, $60, $1d, $00, $42, $68, $b5, $00, $42, $70, $bb, $00
	db $42, $78, $1d, $00

;@ def HideNextRoundPrompt()
;@ path: versus/results
;@ Hides the 9 prompt sprites (Y = 0).
;@ clobbers: a, b, de, hl
;@ sig: ecb1f209
HideNextRoundPrompt::
;> p = addr(wShadowOAM) + 0x60
	ld hl, wShadowOAM + $60
	ld de, $0004
;>@loop for i in range(9):
	ld b, $09
	xor a

;>     mem[p] = 0
.loop
	ld [hl], a
;>     p += 4
	add hl, de
;=@loop
	dec b
	jr nz, .loop

;> return
	ret


;@ def ShowVersusTally()
;@ path: versus/results
;@ The screen between 2-player rounds: Mario and Luigi with a cup for every
;@ round won, and "MARIO WINS" / "LUIGI WINS" when the match is over.
;@ reads: hSerialRole, hRoundTie, hVersusWins, hVersusLosses, hAdvantageMe, hAdvantageOpponent, hDeuce
;@ writes: hTemp, rLCDC
;@ test: skip switches the LCD off
;@ sig: 026f426e
ShowVersusTally::
;> DisableLCD()
	call DisableLCD
;> LoadTilesToVRAM(CutsceneTiles, 0x1000)
	ld hl, CutsceneTiles
	ld bc, $1000
	call LoadTilesToVRAM
;> ClearBGMap0()
	call ClearBGMap0
;> rest = CopyTilemapRows(VersusTallyTilemap, vBGMap0, 4)
	ld hl, vBGMap0
	ld de, VersusTallyTilemap
	ld b, $04
	call CopyTilemapRows
;> CopyTilemapRows(rest, vBGMap0 + 0x180, 6)
	ld hl, vBGMap0 + $180
	ld b, $06
	call CopyTilemapRows
;> if hSerialRole == SERIAL_MASTER:                 # swap the two name labels
	ldh a, [hSerialRole]
	cp SERIAL_MASTER
	jr nz, .scores

;>     mem[vBGMap0 + 0x041] = 0xBD
	ld hl, vBGMap0 + $041
	ld [hl], $bd
;>     mem[vBGMap0 + 0x042] = 0xB2
	inc l
	ld [hl], $b2
;>     mem[vBGMap0 + 0x043] = 0x2E
	inc l
	ld [hl], $2e
;>     mem[vBGMap0 + 0x044] = 0xBE
	inc l
	ld [hl], $be
;>     mem[vBGMap0 + 0x045] = 0x2E
	inc l
	ld [hl], $2e
;>     mem[vBGMap0 + 0x201] = 0xB4
	ld hl, vBGMap0 + $201
	ld [hl], $b4
;>     mem[vBGMap0 + 0x202] = 0xB5
	inc l
	ld [hl], $b5
;>     mem[vBGMap0 + 0x203] = 0xBB
	inc l
	ld [hl], $bb
;>     mem[vBGMap0 + 0x204] = 0x2E
	inc l
	ld [hl], $2e
;>     mem[vBGMap0 + 0x205] = 0xBC
	inc l
	ld [hl], $bc

;> if not hRoundTie:
.scores
	ldh a, [hRoundTie]
	and a
	jr nz, .wins

;>     UpdateDeuce()
	call UpdateDeuce

;> cups = hVersusWins                               # our cups, bottom half
.wins
	ldh a, [hVersusWins]
;> if cups:
	and a
	jr z, .losses

;>     if cups == 5:
	cp $05
	jr nz, .myCups

;>         dest = vBGMap0 + 0x0A5
	ld hl, vBGMap0 + $0A5
;>         count = 11
	ld b, $0b
;>         master = hSerialRole == SERIAL_MASTER
	ldh a, [hSerialRole]
	cp SERIAL_MASTER
;>         text = MarioWinsText
	ld de, MarioWinsText
;>         if not master:
	jr z, .myText

;>             text = LuigiWinsText
	ld de, LuigiWinsText

;>         DrawVersusText(dest, text, count)
.myText
	call DrawVersusText
;>         cups = 4
	ld a, $04

;>     count = cups
.myCups
	ld c, a
;>     master = hSerialRole == SERIAL_MASTER
	ldh a, [hSerialRole]
	cp SERIAL_MASTER
;>     tiles = 0x93                                 # cup tiles: Luigi's colour
	ld a, $93
;>     if master:
	jr nz, .myCupTiles

;>         tiles = 0x8F                             # Mario's colour
	ld a, $8f

;>     hTemp = tiles
.myCupTiles
	ldh [hTemp], a
;>     DrawCups(vBGMap0 + 0x1E7, count)
	ld hl, vBGMap0 + $1E7
	call DrawCups
;>     if hAdvantageMe:
	ldh a, [hAdvantageMe]
	and a
	jr z, .losses

;>         hTemp = 0xAC
	ld a, $ac
	ldh [hTemp], a
;>         DrawCups(vBGMap0 + 0x1F0, 1)
	ld hl, vBGMap0 + $1F0
	ld c, $01
	call DrawCups
;>         DrawVersusText(vBGMap0 + 0x0A6, AdvantageText, 9)
	ld hl, vBGMap0 + $0A6
	ld de, AdvantageText
	ld b, $09
	call DrawVersusText

;> cups = hVersusLosses                             # the opponent's cups, top half
.losses
	ldh a, [hVersusLosses]
;> if cups:
	and a
	jr z, .deuce

;>     if cups == 5:
	cp $05
	jr nz, .theirCups

;>         dest = vBGMap0 + 0x0A5
	ld hl, vBGMap0 + $0A5
;>         count = 11
	ld b, $0b
;>         master = hSerialRole == SERIAL_MASTER
	ldh a, [hSerialRole]
	cp SERIAL_MASTER
;>         text = LuigiWinsText
	ld de, LuigiWinsText
;>         if not master:
	jr z, .theirText

;>             text = MarioWinsText
	ld de, MarioWinsText

;>         DrawVersusText(dest, text, count)
.theirText
	call DrawVersusText
;>         cups = 4
	ld a, $04

;>     count = cups
.theirCups
	ld c, a
;>     master = hSerialRole == SERIAL_MASTER
	ldh a, [hSerialRole]
	cp SERIAL_MASTER
;>     tiles = 0x8F
	ld a, $8f
;>     if master:
	jr nz, .theirCupTiles

;>         tiles = 0x93
	ld a, $93

;>     hTemp = tiles
.theirCupTiles
	ldh [hTemp], a
;>     DrawCups(vBGMap0 + 0x027, count)
	ld hl, vBGMap0 + $027
	call DrawCups
;>     if hAdvantageOpponent:
	ldh a, [hAdvantageOpponent]
	and a
	jr z, .deuce

;>         hTemp = 0xAC
	ld a, $ac
	ldh [hTemp], a
;>         DrawCups(vBGMap0 + 0x030, 1)
	ld hl, vBGMap0 + $030
	ld c, $01
	call DrawCups

;> if hDeuce:
.deuce
	ldh a, [hDeuce]
	and a
	jr z, .done

;>     DrawVersusText(vBGMap0 + 0x0A7, DeuceText, 6)
	ld hl, vBGMap0 + $0A7
	ld de, DeuceText
	ld b, $06
	call DrawVersusText

;> rLCDC = 0xD3
.done
	ld a, $d3
	ldh [rLCDC], a
;> ClearShadowOAM()
	call ClearShadowOAM
;> return
	ret


;@ def DrawCups(dest: hl, count: c)
;@ path: versus/results
;@ Draws `count` cups side by side (2x2 tiles each, starting at tile hTemp).
;@ reads: hTemp
;@ clobbers: a, bc, de, hl
;@ test: dest = rand(0x9800, 0x9B00)
;@ test: count = rand(1, 4)
;@ test: hTemp = rng.choice([0x8F, 0x93, 0xAC])
;@ sig: f2263963
DrawCups::
;>@cup for i in range(count):
;>     t = hTemp
	ldh a, [hTemp]
;>     row = dest
	push hl
	ld de, $0020
;>@row     for r in range(2):
	ld b, $02

;>         mem[row] = t
.row
	push hl
	ld [hli], a
;>         mem[row + 1] = t + 1
	inc a
	ld [hl], a
;>         t += 2
	inc a
;>         row += 32
	pop hl
	add hl, de
;=@row
	dec b
	jr nz, .row

;>     dest += 3
	pop hl
	ld de, $0003
	add hl, de
;=@cup
	dec c
	jr nz, DrawCups

;> return
	ret


;@ def UpdateDeuce()
;@ path: versus/results
;@ After a decisive round: 4 wins become 5 - the match is won (first to 4).
;@ The deuce / advantage handling here is unreachable: hDeuce is never set.
;@ reads: hAdvantageMe, hAdvantageOpponent, hDeuce, hVersusWins, hVersusLosses
;@ writes: hVersusWins, hVersusLosses, hDeuce, hAdvantageMe, hAdvantageOpponent
;@ test: hVersusWins = rand(0, 5)
;@ test: hVersusLosses = rand(0, 5)
;@ test: hAdvantageMe = rng.choice([0, 0, 1])
;@ test: hAdvantageOpponent = rng.choice([0, 0, 1])
;@ test: hDeuce = rng.choice([0, 0, 1])
;@ sig: 7a61738e
UpdateDeuce::
;> # (hl = hVersusWins, de = hVersusLosses)
	ld hl, hVersusWins
	ld de, hVersusLosses
;> if hAdvantageMe:
	ldh a, [hAdvantageMe]
	and a
	jr nz, .advantageMe

;>@am1     if hVersusWins == 5: end = 'won'
;>@am2     else: end = 'keep'
;> elif hAdvantageOpponent:
	ldh a, [hAdvantageOpponent]
	and a
	jr nz, .advantageOpponent

;>@ao1     if hVersusLosses == 5: end = 'lost'
;>@ao2     else: end = 'keep'                         # (the shared .keep code)
;> elif hDeuce:
	ldh a, [hDeuce]
	and a
	jr nz, .deuce

;>@d1     if hVersusWins == 4:
;>@d2         hAdvantageMe = 4
;>     else:
;>@d4         hAdvantageOpponent = hVersusWins
;>@d5     hDeuce = 0
;>@d6     return
;> elif hVersusWins == 4:                           # first to 4 wins the match
	ld a, [hl]
	cp $04
	jr z, .matchWon

;>@w4     end = 'won'
;> elif hVersusLosses == 4:
	ld a, [de]
	cp $04
;=@ret
	ret nz

;>@l4     end = 'lost'
;>@ret else: return
;> if end == 'lost':
;>     hVersusLosses = 5
.matchLost
	ld a, $05
	ld [de], a
	jr .clearDeuce

; unused: ld a, [de] / cp 3 / ret nz
	db $1a, $fe, $03, $c0

;=@am2
.keep
	ld a, $03
	jr .clearAdvantage

;> elif end == 'won':
;>     hVersusWins = 5
.matchWon
	ld [hl], $05

;> if end != 'keep': hDeuce = 0
.clearDeuce
	xor a
	ldh [hDeuce], a

;> hAdvantageMe = 0
.clearAdvantage
	xor a
	ldh [hAdvantageMe], a
;> hAdvantageOpponent = 0
	ldh [hAdvantageOpponent], a
;> return
	ret

;=@d1
.deuce
	ld a, [hl]
	cp $04
	jr nz, .opponentAhead

;=@d2
	ldh [hAdvantageMe], a

;=@d5
.endDeuce
	xor a
	ldh [hDeuce], a
;=@d6
	ret

;=@d4
.opponentAhead
	ldh [hAdvantageOpponent], a
	jr .endDeuce

;=@am1
.advantageMe
	ld a, [hl]
	cp $05
	jr z, .matchWon

	jr .keep

;=@ao1
.advantageOpponent
	ld a, [de]
	cp $05
	jr z, .matchLost

	jr .keep

;@ def DrawVersusText(dest: hl, text: de, count: b)
;@ path: versus/results
;@ Writes `count` tiles of text at dest and an underline (tile $B6) below.
;@ clobbers: a, b, de, hl
;@ test: dest = rand(0x9800, 0x9B00)
;@ test: text = rand(0x0000, 0x7000)
;@ test: count = rand(1, 11)
;@ sig: 501e2d2d
DrawVersusText::
;>@copy for i in range(count):
	push bc
	push hl

;>     mem[dest + i] = mem[text + i]
.copy
	ld a, [de]
	ld [hli], a
	inc de
;=@copy
	dec b
	jr nz, .copy

;> under = dest + 32
	pop hl
	ld de, $0020
	add hl, de
;>@line for i in range(count):
	pop bc
	ld a, $b6

;>     mem[under + i] = 0xB6
.underline
	ld [hli], a
;=@line
	dec b
	jr nz, .underline

;> return
	ret

; "DEUCE!" (6 tiles of CutsceneTiles)
DeuceText::
	db $b0, $b1, $b2, $b3, $b1, $3e

; 11 tiles: shown when Mario (the master) won the match
MarioWinsText::
	db $b4, $b5, $bb, $2e, $bc, $2f, $2d, $2e, $3d, $0e, $3e

; 11 tiles: shown when Luigi (the slave) won the match
LuigiWinsText::
	db $bd, $b2, $2e, $be, $2e, $2f, $2d, $2e, $3d, $0e, $3e

; 9 tiles: shown after deuce for the player with the advantage
AdvantageText::
	db $b5, $b0, $41, $b5, $3d, $1d, $b5, $be, $b1

;@ def State1F_VersusNextRound()
;@ path: versus/results
;@ Game state $1F: once both Game Boys are in step, the next round starts
;@ (or, after a decided match, a new one) at the height select (state $16).
;@ reads: hTimer1, hVersusWins, hVersusLosses
;@ writes: rIE, hRoundTie, hVersusNextRound, hGameState
;@ test: skip talks to the link cable
;@ sig: 0f714c18
State1F_VersusNextRound::
;> rIE = 0x01
	ld a, $01
	ldh [rIE], a
;> if hTimer1: return
	ldh a, [hTimer1]
	and a
	ret nz

;> ClearShadowOAM()
	call ClearShadowOAM
;> hRoundTie = 0
	xor a
	ldh [hRoundTie], a
;> SyncWithPartner(0x27, 0x79)
	ld b, $27
	ld c, $79
	call SyncWithPartner
;> InitSound()
	call InitSound
;> if hVersusWins != 5:
	ldh a, [hVersusWins]
	cp $05
	jr z, .next

;>     if hVersusLosses != 5:
	ldh a, [hVersusLosses]
	cp $05
	jr z, .next

;>         hVersusNextRound = 1                     # match goes on: skip the height select
	ld a, $01
	ldh [hVersusNextRound], a

;> hGameState = 0x16
.next
	ld a, $16
	ldh [hGameState], a
;> return
	ret


;@ def SyncWithPartner(slave_answer: b, master_answer: c)
;@ path: system/link
;@ A two-byte barrier: the master sends $02 until the slave answers
;@ `slave_answer`, then sends `master_answer`; the slave keeps sending
;@ `slave_answer` until it receives `master_answer`. Until then it ends the
;@ caller's frame early (drops the caller's return address).
;@ reads: hSerialDone, hSerialRole, hSerialRx
;@ writes: hSerialDone, hSerialTx, hSerialSendPending
;@ test: skip talks to the link cable and manipulates the stack
;@ sig: 2268767a
SyncWithPartner::
;> if not hSerialDone: return_from_caller()        # (.notYet)
	ldh a, [hSerialDone]
	and a
	jr z, .notYet

;> hSerialDone = 0
	xor a
	ldh [hSerialDone], a
;> if hSerialRole == SERIAL_MASTER:
	ldh a, [hSerialRole]
	cp SERIAL_MASTER
	ldh a, [hSerialRx]
	jr nz, .slave

;>     if hSerialRx == slave_answer:
	cp b
	jr z, .inStep

;>@ack         hSerialTx = master_answer; hSerialSendPending = master_answer
;>@inStep         return                                   # in step
;>     hSerialTx = 2; hSerialSendPending = 2
	ld a, $02
	ldh [hSerialTx], a
	ldh [hSerialSendPending], a

;>     return_from_caller()
.notYet
	pop hl
	ret

;=@ack
.inStep
	ld a, c
	ldh [hSerialTx], a
	ldh [hSerialSendPending], a
;=@inStep
	ret

;> if hSerialRx == master_answer: return            # in step
.slave
	cp c
	ret z

;> hSerialTx = slave_answer
	ld a, b
	ldh [hSerialTx], a
;> return_from_caller()
	pop hl
	ret


;@ def State26_ShuttleInit()
;@ path: endings/shuttle
;@ Game state $26 (type B won at height 5): the space shuttle ending. Shows
;@ the launch pad with the shuttle on it (3 objects: shuttle, 2 smoke clouds).
;@ writes: hTimer1, hGameState, wMusicRequest
;@ test: skip switches the LCD off
;@ sig: 19c49db9
State26_ShuttleInit::
;> ShowLaunchPad()
	call ShowLaunchPad
;> CopyTileColumn(vBGMap1 + 0xE6, LaunchTowerColumns, 7)       # the shuttle's tower
	ld hl, vBGMap1 + $E6
	ld de, LaunchTowerColumns
	ld b, $07
	call CopyTileColumn
;> CopyTileColumn(vBGMap1 + 0xE7, LaunchTowerColumns + 7, 7)
	ld hl, vBGMap1 + $E7
	ld de, LaunchTowerColumns + 7
	ld b, $07
	call CopyTileColumn
;> mem[vBGMap1 + 0x108] = 0x72                      # its base
	ld hl, vBGMap1 + $108
	ld [hl], $72
;> mem[vBGMap1 + 0x109] = 0xC4
	inc l
	ld [hl], $c4
;> mem[vBGMap1 + 0x128] = 0xB7
	ld hl, vBGMap1 + $128
	ld [hl], $b7
;> mem[vBGMap1 + 0x129] = 0xB8
	inc l
	ld [hl], $b8
;> SetupObjects(wObjects, ShuttleObjects, 3)
	ld de, ShuttleObjects
	ld hl, wObjects
	ld c, $03
	call SetupObjects
;> DrawObjectsAt0(3)
	ld a, $03
	call DrawObjectsAt0
;> rLCDC = 0xDB                                     # BG map 1
	ld a, $db
	ldh [rLCDC], a
;> hTimer1 = 0xBB
	ld a, $bb
	ldh [hTimer1], a
;> hGameState = 0x27
	ld a, $27
	ldh [hGameState], a
;> wMusicRequest = 0x10
	ld a, $10
	ld [wMusicRequest], a
;> return
	ret


;@ def ShowLaunchPad()
;@ path: endings/shuttle
;@ Shared by both endings: loads CutsceneTiles and draws the launch pad and a
;@ tower on BG map 1.
;@ test: skip switches the LCD off
;@ sig: 04fb6fd0
ShowLaunchPad::
;> DisableLCD()
	call DisableLCD
;> LoadTilesToVRAM(CutsceneTiles, 0x1000)
	ld hl, CutsceneTiles
	ld bc, $1000
	call LoadTilesToVRAM
;> ClearTilemap(vBGMap1 + 0x3FF)
	ld hl, vBGMap1 + $3FF
	call ClearTilemap
;> CopyTilemapRows(LaunchPadTilemap, vBGMap1 + 0x1C0, 4)
	ld hl, vBGMap1 + $1C0
	ld de, LaunchPadTilemap
	ld b, $04
	call CopyTilemapRows
;> CopyTileColumn(vBGMap1 + 0xEC, LaunchTowerColumns + 14, 7)
	ld hl, vBGMap1 + $EC
	ld de, LaunchTowerColumns + 14
	ld b, $07
	call CopyTileColumn
;> CopyTileColumn(vBGMap1 + 0xED, LaunchTowerColumns + 21, 7)
	ld hl, vBGMap1 + $ED
	ld de, LaunchTowerColumns + 21
	ld b, $07
	call CopyTileColumn
;> return
	ret


;@ def State27_ShuttleSmoke()
;@ path: endings/shuttle
;@ Game state $27: after a while the smoke clouds appear.
;@ reads: hTimer1
;@ writes: wObjects, hTimer1, hGameState
;@ test: hTimer1 = rng.choice([0, 3])
;@ sig: 4c4c5576
State27_ShuttleSmoke::
;> if hTimer1: return
	ldh a, [hTimer1]
	and a
	ret nz

;> wObjects[0x10] = 0                               # show both clouds
	ld hl, wObjects + $10
	ld [hl], $00
;> wObjects[0x20] = 0
	ld l, $20
	ld [hl], $00
;> hTimer1 = 0xFF
	ld a, $ff
	ldh [hTimer1], a
;> hGameState = 0x28
	ld a, $28
	ldh [hGameState], a
;> return
	ret


;@ def State28_ShuttleIgnition()
;@ path: endings/shuttle
;@ Game state $28: the clouds flicker; then they grow (sprite $35) and the
;@ board area is cleared.
;@ reads: hTimer1
;@ writes: hGameState, wObjects, hTimer1
;@ test: skip FlickerSmoke and FillBoardAndRefresh draw sprites/board only; covered by their own tests
;@ sig: 5dfd4ef9
State28_ShuttleIgnition::
;> if hTimer1:
	ldh a, [hTimer1]
	and a
	jr z, .next

;>     FlickerSmoke()
	call FlickerSmoke
;>     return
	ret

;> hGameState = 0x29
.next
	ld a, $29
	ldh [hGameState], a
;> wObjects[0x13] = 0x35                            # bigger clouds
	ld hl, wObjects + $13
	ld [hl], $35
;> wObjects[0x23] = 0x35
	ld l, $23
	ld [hl], $35
;> hTimer1 = 0xFF
	ld a, $ff
	ldh [hTimer1], a
;> FillBoardAndRefresh(TILE_BLANK)
	ld a, TILE_BLANK
	call FillBoardAndRefresh
;> return
	ret


;@ def State29_ShuttleRelease()
;@ path: endings/shuttle
;@ Game state $29: more flickering smoke, then the shuttle's base tiles are
;@ removed and it lifts off (state $02).
;@ reads: hTimer1
;@ writes: hGameState
;@ test: skip waits for the LCD
;@ sig: 357e5760
State29_ShuttleRelease::
;> if hTimer1:
	ldh a, [hTimer1]
	and a
	jr z, .next

;>     FlickerSmoke()
	call FlickerSmoke
;>     return
	ret

;> hGameState = 0x02
.next
	ld a, $02
	ldh [hGameState], a
;> WriteTileB(TILE_BLANK, vBGMap1 + 0x108)          # remove the shuttle's base
	ld hl, vBGMap1 + $108
	ld b, TILE_BLANK
	call WriteTileB
;> WriteTileB(TILE_BLANK, vBGMap1 + 0x109)
	ld hl, vBGMap1 + $109
	call WriteTileB
;> WriteTileB(TILE_BLANK, vBGMap1 + 0x128)
	ld hl, vBGMap1 + $128
	call WriteTileB
;> WriteTileB(TILE_BLANK, vBGMap1 + 0x129)
	ld hl, vBGMap1 + $129
	call WriteTileB
;> return
	ret


;@ def State02_ShuttleLiftoff()
;@ path: endings/shuttle
;@ Game state $02: the shuttle rises slowly; at y = $58 the clouds give way
;@ to the engine flame (object 1, sprite $40) and it really launches.
;@ reads: hTimer1, wObjects
;@ writes: hTimer1, wObjects, hGameState, wNoiseSFXRequest
;@ test: hTimer1 = rng.choice([0, 0, 5])
;@ test: hTimer2 = rng.choice([0, 4])
;@ test: mem[0xC201] = rng.choice([0x59, 0x70])
;@ test: for i in range(3): mem[0xC200 + 16 * i] = rng.choice([0, 0x80]); mem[0xC203 + 16 * i] = rng.choice([0x40, 0x41, 0x35])
;@ test: hObjHidden = 0
;@ sig: 1438f6ec
State02_ShuttleLiftoff::
;> if not hTimer1:
	ldh a, [hTimer1]
	and a
	jr nz, .flicker

;>     hTimer1 = 10
	ld a, $0a
	ldh [hTimer1], a
;>     wObjects[1] -= 1                             # one pixel up
	ld hl, wObjects + $01
	dec [hl]
;>     if wObjects[1] == 0x58:
	ld a, [hl]
	cp $58
	jr nz, .flicker

;>         wObjects[0x10] = 0                       # the flame below the shuttle
	ld hl, wObjects + $10
	ld [hl], $00
;>         wObjects[0x11] = 0x58 + 0x20
	inc l
	add $20
	ld [hli], a
;>         wObjects[0x12] = 0x4C
	ld [hl], $4c
;>         wObjects[0x13] = 0x40
	inc l
	ld [hl], $40
;>         wObjects[0x20] = 0x80                    # one cloud goes
	ld l, $20
	ld [hl], $80
;>         DrawObjectsAt0(3)
	ld a, $03
	call DrawObjectsAt0
;>         hGameState = 0x03
	ld a, $03
	ldh [hGameState], a
;>         wNoiseSFXRequest = 4                     # rocket noise
	ld a, $04
	ld [wNoiseSFXRequest], a
;>         return
	ret

;> FlickerSmoke()
.flicker
	call FlickerSmoke
;> return
	ret


;@ def State03_ShuttleFlight()
;@ path: endings/shuttle
;@ Game state $03: shuttle and flame fly up out of the screen (the flame
;@ flickers every 6 frames); then the message is typed (state $2C).
;@ reads: hTimer1, hTimer2, wObjects
;@ writes: hTimer1, wObjects, hMessagePosHi, hMessagePosLo, hGameState, hTimer2
;@ test: hTimer1 = rng.choice([0, 0, 5])
;@ test: hTimer2 = rng.choice([0, 4])
;@ test: mem[0xC201] = rng.choice([0xD1, 0x70])
;@ test: for i in range(3): mem[0xC200 + 16 * i] = rng.choice([0, 0x80]); mem[0xC203 + 16 * i] = rng.choice([0x40, 0x41])
;@ test: hObjHidden = 0
;@ sig: e3293fce
State03_ShuttleFlight::
;> if not hTimer1:
	ldh a, [hTimer1]
	and a
	jr nz, .animate

;>     hTimer1 = 10
	ld a, $0a
	ldh [hTimer1], a
;>     wObjects[0x11] -= 1                          # flame and shuttle one pixel up
	ld hl, wObjects + $11
	dec [hl]
;>     wObjects[1] -= 1
	ld l, $01
	dec [hl]
;>     if wObjects[1] == 0xD0:                      # gone (wrapped above the screen)
	ld a, [hl]
	cp $d0
	jr nz, .animate

;>         hMessagePosHi = 0x9C
	ld a, HIGH(vBGMap1 + $82)
	ldh [hMessagePosHi], a
;>         hMessagePosLo = 0x82
	ld a, LOW(vBGMap1 + $82)
	ldh [hMessagePosLo], a
;>         hGameState = 0x2C
	ld a, $2c
	ldh [hGameState], a
;>         return
	ret

;> if not hTimer2:
.animate
	ldh a, [hTimer2]
	and a
	jr nz, .draw

;>     hTimer2 = 6
	ld a, $06
	ldh [hTimer2], a
;>     wObjects[0x13] ^= 1                          # flame animation
	ld hl, wObjects + $13
	ld a, [hl]
	xor $01
	ld [hl], a

;> DrawObjectsAt0(3)
.draw
	ld a, $03
	call DrawObjectsAt0
;> return
	ret


;@ def State2C_TypeMessage()
;@ path: endings/shuttle
;@ Game state $2C: types EndingMessage letter by letter (one every 6
;@ frames, with a sound and an underline tile below each letter).
;@ reads: hTimer1, hMessagePosHi, hMessagePosLo
;@ writes: hTimer1, wSFXRequest, hMessagePosHi, hMessagePosLo, hGameState
;@ test: skip waits for the LCD
;@ sig: a1339153
State2C_TypeMessage::
;> if hTimer1: return
	ldh a, [hTimer1]
	and a
	ret nz

;> hTimer1 = 6
	ld a, $06
	ldh [hTimer1], a
;> i = hMessagePosLo - 0x82                         # letter number
	ldh a, [hMessagePosLo]
	sub $82
	ld e, a
	ld d, $00
;> src = EndingMessage + i
	ld hl, EndingMessage
	add hl, de
	push hl
	pop de
;> pos = hMessagePosHi << 8 | hMessagePosLo
	ldh a, [hMessagePosHi]
	ld h, a
	ldh a, [hMessagePosLo]
	ld l, a
;> WriteTileA(mem[src], pos)
	ld a, [de]
	call WriteTileA
;> under = pos + 32
	push hl
	ld de, $0020
	add hl, de
;> WriteTileB(0xB6, under)                          # underline
	ld b, $b6
	call WriteTileB
	pop hl
;> pos += 1
	inc hl
;> wSFXRequest = 2
	ld a, $02
	ld [wSFXRequest], a
;> hMessagePosHi = hi(pos)
	ld a, h
	ldh [hMessagePosHi], a
;> hMessagePosLo = lo(pos)
	ld a, l
	ldh [hMessagePosLo], a
;> if lo(pos) != 0x92: return                       # $92: all 16 letters typed
	cp $92
	ret nz

;> hTimer1 = 0xFF
	ld a, $ff
	ldh [hTimer1], a
;> hGameState = 0x2D
	ld a, $2d
	ldh [hGameState], a
;> return
	ret

; The 16 letters typed at the end of the shuttle ending (tiles of CutsceneTiles)
EndingMessage::
	db $b3, $bc, $3d, $be, $bb, $b5, $1d, $b2, $bd, $b5, $1d, $2e, $bc, $3d, $0e, $3e

;@ def State2D_ShuttleEnd()
;@ path: endings/shuttle
;@ Game state $2D: back to the normal tiles and on to the type B tally.
;@ writes: rLCDC, hGameState
;@ reads: hTimer1
;@ test: skip switches the LCD off
;@ sig: 5106ef7c
State2D_ShuttleEnd::
;> if hTimer1: return
	ldh a, [hTimer1]
	and a
	ret nz

;> DisableLCD()
	call DisableLCD
;> LoadGameTiles()
	call LoadGameTiles
;> ClearClearedRows()
	call ClearClearedRows
;> rLCDC = 0x93
	ld a, $93
	ldh [rLCDC], a
;> hGameState = 0x05                                # State05_TypeBTally
	ld a, $05
	ldh [hGameState], a
;> return
	ret


;@ def State34_RocketWait()
;@ path: endings/rocket
;@ Game state $34 (type A, 100000+ points): a pause before the rocket ending.
;@ reads: hTimer1
;@ writes: hGameState
;@ test: hTimer1 = rng.choice([0, 3])
;@ sig: ddfa7c98
State34_RocketWait::
;> if hTimer1: return
	ldh a, [hTimer1]
	and a
	ret nz

;> hGameState = 0x2E
	ld a, $2e
	ldh [hGameState], a
;> return
	ret


;@ def State2E_RocketInit()
;@ path: endings/rocket
;@ Game state $2E: the launch pad with a rocket whose size depends on the
;@ score (hRocketSprite), plus two smoke clouds.
;@ reads: hRocketSprite
;@ writes: wObjects, hRocketSprite, rLCDC, hTimer1, hGameState, wMusicRequest
;@ test: skip switches the LCD off
;@ sig: 0e68f0d3
State2E_RocketInit::
;> ShowLaunchPad()
	call ShowLaunchPad
;> SetupObjects(wObjects, RocketObjects, 3)
	ld de, RocketObjects
	ld hl, wObjects
	ld c, $03
	call SetupObjects
;> wObjects[3] = hRocketSprite
	ldh a, [hRocketSprite]
	ld [wObjects + $03], a
;> DrawObjectsAt0(3)
	ld a, $03
	call DrawObjectsAt0
;> hRocketSprite = 0
	xor a
	ldh [hRocketSprite], a
;> rLCDC = 0xDB                                     # BG map 1
	ld a, $db
	ldh [rLCDC], a
;> hTimer1 = 0xBB
	ld a, $bb
	ldh [hTimer1], a
;> hGameState = 0x2F
	ld a, $2f
	ldh [hGameState], a
;> wMusicRequest = 0x10
	ld a, $10
	ld [wMusicRequest], a
;> return
	ret


;@ def State2F_RocketSmoke()
;@ path: endings/rocket
;@ Game state $2F: after a while the smoke clouds appear.
;@ reads: hTimer1
;@ writes: wObjects, hTimer1, hGameState
;@ test: hTimer1 = rng.choice([0, 3])
;@ sig: 55e7cb6c
State2F_RocketSmoke::
;> if hTimer1: return
	ldh a, [hTimer1]
	and a
	ret nz

;> wObjects[0x10] = 0
	ld hl, wObjects + $10
	ld [hl], $00
;> wObjects[0x20] = 0
	ld l, $20
	ld [hl], $00
;> hTimer1 = 0xA0
	ld a, $a0
	ldh [hTimer1], a
;> hGameState = 0x30
	ld a, $30
	ldh [hGameState], a
;> return
	ret


;@ def State30_RocketIgnition()
;@ path: endings/rocket
;@ Game state $30: the smoke flickers, then the board area is cleared.
;@ reads: hTimer1
;@ writes: hGameState, hTimer1
;@ test: hTimer1 = rng.choice([0, 3])
;@ test: hTimer2 = rng.choice([0, 4])
;@ test: for i in range(3): mem[0xC200 + 16 * i] = rng.choice([0, 0x80]); mem[0xC203 + 16 * i] = rng.choice([0x35, 0x58, 0x5A])
;@ test: hObjHidden = 0
;@ sig: a32bb835
State30_RocketIgnition::
;> if hTimer1:
	ldh a, [hTimer1]
	and a
	jr z, .next

;>     FlickerSmoke()
	call FlickerSmoke
;>     return
	ret

;> hGameState = 0x31
.next
	ld a, $31
	ldh [hGameState], a
;> hTimer1 = 0x80
	ld a, $80
	ldh [hTimer1], a
;> FillBoardAndRefresh(TILE_BLANK)
	ld a, TILE_BLANK
	call FillBoardAndRefresh
;> return
	ret


;@ def State31_RocketLiftoff()
;@ path: endings/rocket
;@ Game state $31: the rocket rises slowly; at y = $6A the clouds give way to
;@ the flame (object 1, sprite $54) and it launches.
;@ reads: hTimer1, wObjects
;@ writes: hTimer1, wObjects, hGameState, wNoiseSFXRequest
;@ test: hTimer1 = rng.choice([0, 0, 5])
;@ test: hTimer2 = rng.choice([0, 4])
;@ test: mem[0xC201] = rng.choice([0x6B, 0x80])
;@ test: for i in range(3): mem[0xC200 + 16 * i] = rng.choice([0, 0x80]); mem[0xC203 + 16 * i] = rng.choice([0x35, 0x58, 0x5A])
;@ test: hObjHidden = 0
;@ sig: 44d506cf
State31_RocketLiftoff::
;> if not hTimer1:
	ldh a, [hTimer1]
	and a
	jr nz, .flicker

;>     hTimer1 = 10
	ld a, $0a
	ldh [hTimer1], a
;>     wObjects[1] -= 1
	ld hl, wObjects + $01
	dec [hl]
;>     if wObjects[1] == 0x6A:
	ld a, [hl]
	cp $6a
	jr nz, .flicker

;>         wObjects[0x10] = 0                       # the flame
	ld hl, wObjects + $10
	ld [hl], $00
;>         wObjects[0x11] = 0x6A + 0x10
	inc l
	add $10
	ld [hli], a
;>         wObjects[0x12] = 0x54
	ld [hl], $54
;>         wObjects[0x13] = 0x5C
	inc l
	ld [hl], $5c
;>         wObjects[0x20] = 0x80
	ld l, $20
	ld [hl], $80
;>         DrawObjectsAt0(3)
	ld a, $03
	call DrawObjectsAt0
;>         hGameState = 0x32
	ld a, $32
	ldh [hGameState], a
;>         wNoiseSFXRequest = 4
	ld a, $04
	ld [wNoiseSFXRequest], a
;>         return
	ret

;> FlickerSmoke()
.flicker
	call FlickerSmoke
;> return
	ret


;@ def State32_RocketFlight()
;@ path: endings/rocket
;@ Game state $32: rocket and flame fly up out of the screen (the flame
;@ flickers every 6 frames).
;@ reads: hTimer1, hTimer2, wObjects
;@ writes: hTimer1, wObjects, hGameState, hTimer2
;@ test: hTimer1 = rng.choice([0, 0, 5])
;@ test: hTimer2 = rng.choice([0, 4])
;@ test: mem[0xC201] = rng.choice([0xE1, 0x70])
;@ test: for i in range(3): mem[0xC200 + 16 * i] = rng.choice([0, 0x80]); mem[0xC203 + 16 * i] = rng.choice([0x5C, 0x5D])
;@ test: hObjHidden = 0
;@ sig: 5d4acf21
State32_RocketFlight::
;> if not hTimer1:
	ldh a, [hTimer1]
	and a
	jr nz, .animate

;>     hTimer1 = 10
	ld a, $0a
	ldh [hTimer1], a
;>     wObjects[0x11] -= 1
	ld hl, wObjects + $11
	dec [hl]
;>     wObjects[1] -= 1
	ld l, $01
	dec [hl]
;>     if wObjects[1] == 0xE0:                      # gone
	ld a, [hl]
	cp $e0
	jr nz, .animate

;>         hGameState = 0x33
	ld a, $33
	ldh [hGameState], a
;>         return
	ret

;> if not hTimer2:
.animate
	ldh a, [hTimer2]
	and a
	jr nz, .draw

;>     hTimer2 = 6
	ld a, $06
	ldh [hTimer2], a
;>     wObjects[0x13] ^= 1
	ld hl, wObjects + $13
	ld a, [hl]
	xor $01
	ld [hl], a

;> DrawObjectsAt0(3)
.draw
	ld a, $03
	call DrawObjectsAt0
;> return
	ret


;@ def State33_RocketEnd()
;@ path: endings/rocket
;@ Game state $33: back to the normal tiles and to the type A level select.
;@ writes: rLCDC, hGameState
;@ test: skip switches the LCD off
;@ sig: adaaa91b
State33_RocketEnd::
;> DisableLCD()
	call DisableLCD
;> LoadGameTiles()
	call LoadGameTiles
;> InitSound()
	call InitSound
;> ClearClearedRows()
	call ClearClearedRows
;> rLCDC = 0x93
	ld a, $93
	ldh [rLCDC], a
;> hGameState = 0x10                                # State10_TypeALevelInit
	ld a, $10
	ldh [hGameState], a
;> return
	ret


;@ def FlickerSmoke()
;@ path: endings/shared
;@ Every 10 frames (hTimer2): a smoke sound, and the two clouds (objects 1
;@ and 2) toggle between visible and hidden.
;@ reads: hTimer2
;@ writes: hTimer2, wNoiseSFXRequest, wObjects
;@ test: hTimer2 = rng.choice([0, 0, 4])
;@ test: for i in range(3): mem[0xC200 + 16 * i] = rng.choice([0, 0x80]); mem[0xC203 + 16 * i] = rng.choice([0x35, 0x58, 0x5A])
;@ test: hObjHidden = 0
;@ sig: 409a054d
FlickerSmoke::
;> if hTimer2: return
	ldh a, [hTimer2]
	and a
	ret nz

;> hTimer2 = 10
	ld a, $0a
	ldh [hTimer2], a
;> wNoiseSFXRequest = 3
	ld a, $03
	ld [wNoiseSFXRequest], a
;>@loop for obj in (0x10, 0x20):                   # objects 1 and 2
	ld b, $02
	ld hl, wObjects + $10

;>     wObjects[obj] ^= 0x80
.toggle
	ld a, [hl]
	xor $80
	ld [hl], a
;=@loop
	ld l, $20
	dec b
	jr nz, .toggle

;> DrawObjectsAt0(3)
	ld a, $03
	call DrawObjectsAt0
;> return
	ret

; Four columns of 7 tiles for the launch towers
LaunchTowerColumns::
	db $c2, $ca, $ca, $ca, $ca, $ca, $ca, $c3, $cb, $58, $48, $48, $48, $48, $c8, $73
	db $73, $73, $73, $73, $73, $c9, $74, $74, $74, $74, $74, $74

;@ def CopyTileColumn(dest: hl, src: de, count: b) -> de
;@ path: endings/shared
;@ Writes `count` tiles from src downwards from dest (32 bytes per map row).
;@ clobbers: a, b, hl
;@ test: dest = rand(0x9800, 0x9BFF)
;@ test: src = rand(0x0000, 0x7000)
;@ test: count = rand(1, 18)
;@ sig: 10a8d163
CopyTileColumn::
;>@loop for _ in range(count):
;>     mem[dest] = mem[src]
	ld a, [de]
	ld [hl], a
;>     src = u16(src + 1)
	inc de
;>     dest = u16(dest + 32)                        # next map row
	push de
	ld de, $0020
	add hl, de
	pop de
;=@loop
	dec b
	jr nz, CopyTileColumn

;> return src
	ret


;@ def State08_GameMenuInit()
;@ path: screens/menus
;@ Game state $08: switches the link cable off and shows the game/music menu.
;@ writes: rIE, rSB, rSC, rIF
;@ test: skip switches the LCD off
;@ sig: 63d9d75b
State08_GameMenuInit::
;> rIE = 0x01                                       # VBlank only
	ld a, $01
	ldh [rIE], a
;> rSB = 0; rSC = 0; rIF = 0
	xor a
	ldh [rSB], a
	ldh [rSC], a
	ldh [rIF], a
;> ShowGameMenu()                                   # falls through

;@ def ShowGameMenu()
;@ path: screens/menus
;@ Builds the GAME TYPE / MUSIC TYPE screen with its two cursors, starts the
;@ selected music and continues in state $0E (game type). The stored game
;@ type ($37/$77) is also the X position of its cursor, and the music type
;@ ($1C-$1F) is the sprite id of its label.
;@ reads: hGameType
;@ writes: hGameState
;@ test: skip switches the LCD off
;@ sig: 90bfb2ca
ShowGameMenu::
;> DisableLCD()
	call DisableLCD
;> LoadGameTiles()
	call LoadGameTiles
;> LoadScreen(GameMusicTypeTilemap)
	ld de, GameMusicTypeTilemap
	call LoadScreen
;> ClearShadowOAM()
	call ClearShadowOAM
;> SetupObjects(wObjects, MenuObjects, 2)           # 0: music cursor, 1: game type cursor
	ld hl, wObjects
	ld de, MenuObjects
	ld c, $02
	call SetupObjects
;> MoveMusicCursorWithSFX(addr(wObjects) + 1)
	ld de, wObjects + $01
	call MoveMusicCursorWithSFX
;> wObjects[0x12] = hGameType                       # game type cursor X
	ldh a, [hGameType]
	ld e, $12
	ld [de], a
	inc de
;> if hGameType == GAME_TYPE_A:
	cp GAME_TYPE_A
;>     label = 0x1C                                 # "A-TYPE"
	ld a, $1c
	jr z, .setLabel

;> else:
;>     label = 0x1D                                 # "B-TYPE"
	ld a, $1d

;> wObjects[0x13] = label
.setLabel
	ld [de], a
;> DrawTwoObjects()
	call DrawTwoObjects
;> PlaySelectedMusic()
	call PlaySelectedMusic
;> rLCDC = 0xD3
	ld a, $d3
	ldh [rLCDC], a
;> hGameState = 0x0E                                # State0E_GameTypeMenu
	ld a, $0e
	ldh [hGameState], a

;@ def State09_Nothing()
;@ path: screens/menus
;@ Game state $09: does nothing (a lone `ret`).
;@ sig: 30ba9599
State09_Nothing::
;> return
	ret


;@ def MoveMusicCursorWithSFX(dest: de) -> de
;@ path: screens/menus
;@ Plays the menu sound, then PlaceMusicCursor.
;@ writes: wSFXRequest
;@ test: dest = rand_ram(3)
;@ test: hMusicType = rand(0x1C, 0x1F)
;@ sig: 8ce8ff40
MoveMusicCursorWithSFX::
;> wSFXRequest = 1
	ld a, $01
	ld [wSFXRequest], a
;> return PlaceMusicCursor(dest)                    # falls through

;@ def PlaceMusicCursor(dest: de) -> de
;@ path: screens/menus
;@ Writes the music cursor's y, x and sprite id (= hMusicType) to dest.
;@ reads: hMusicType
;@ clobbers: a, bc, hl
;@ test: dest = rand_ram(3)
;@ test: hMusicType = rand(0x1C, 0x1F)
;@ sig: 63cf7760
PlaceMusicCursor::
;> music = hMusicType
	ldh a, [hMusicType]
	push af
;> offset = u8(2 * u8(music - 0x1C))
	sub $1c
	add a
;> pos = MusicCursorPositions + offset
	ld c, a
	ld b, $00
	ld hl, MusicCursorPositions
	add hl, bc
;> mem[dest] = mem[pos]                             # y
	ld a, [hli]
	ld [de], a
;> dest += 1
	inc de
;> mem[dest] = mem[pos + 1]                         # x
	ld a, [hl]
	ld [de], a
;> dest += 1
	inc de
;> mem[dest] = music                                # sprite id
	pop af
	ld [de], a
;> return dest
	ret

; (y, x) of the music cursor for music types $1C-$1F
MusicCursorPositions::
	db $70, $37, $70, $77, $80, $37, $80, $77

;@ def State0F_MusicMenu()
;@ path: screens/menus
;@ Game state $0F: choosing the music. The four songs sit in a 2x2 grid;
;@ moving the cursor plays the song right away. Start/A confirms, B goes
;@ back to the game type (not in a 2-player game).
;@ reads: hMusicType, hTwoPlayer
;@ writes: hMusicType, hGameState
;@ test: hJoyPressed = rng.choice([0, BTN_START, BTN_A, BTN_B, BTN_RIGHT, BTN_LEFT, BTN_UP, BTN_DOWN])
;@ test: hTimer1 = rng.choice([0, 3])
;@ test: hMusicType = rand(0x1C, 0x1F)
;@ test: hTwoPlayer = rng.choice([0, 1])
;@ test: hGameType = rng.choice([GAME_TYPE_A, GAME_TYPE_B])
;@ test: for i in range(2): mem[0xC200 + 16 * i] = rng.choice([0, 0x80])
;@ test: for i in range(2): mem[0xC203 + 16 * i] = rand(0x1C, 0x1F)
;@ test: hObjHidden = 0
;@ sig: 98488bab
State0F_MusicMenu::
;> buttons = BlinkObject(addr(wObjects))            # the music cursor blinks
	ld de, wObjects
	call BlinkObject
;> music = hMusicType
	ld hl, hMusicType
	ld a, [hl]
;> if buttons & BTN_START: return ConfirmGameMenu(addr(wObjects))
	bit 3, b
	jp nz, ConfirmGameMenu

;> if buttons & BTN_A: return ConfirmGameMenu(addr(wObjects))
	bit 0, b
	jp nz, ConfirmGameMenu

;>@b if buttons & BTN_B:                           # back to the game type
	bit 1, b
	jr nz, .back

;>@tp     if not hTwoPlayer:
;>@gt         hGameState = 0x0E
;>         wObjects[0] = 0                          # stop blinking
;>@rd         return RedrawMenuCursors()
;> if buttons & BTN_RIGHT:
.directions
	inc e
	bit 4, b
	jr nz, .right

;>@r1     if music in (0x1D, 0x1F): return DrawTwoObjects()
;>@r2     new = music + 1
;> elif buttons & BTN_LEFT:
	bit 5, b
	jr nz, .left

;>@l1     if music in (0x1C, 0x1E): return DrawTwoObjects()
;>@l2     new = music - 1
;> elif buttons & BTN_UP:
	bit 6, b
	jr nz, .up

;>@u1     if music < 0x1E: return DrawTwoObjects()
;>@u2     new = music - 2
;> elif not (buttons & BTN_DOWN): return RedrawMenuCursors()
	bit 7, b
	jp z, RedrawMenuCursors

;> else:
;>     if music >= 0x1E: return DrawTwoObjects()
	cp $1e
	jr nc, .draw

;>     new = music + 2
	add $02

;> hMusicType = new
.set
	ld [hl], a
;> MoveMusicCursorWithSFX(addr(wObjects) + 1)
	call MoveMusicCursorWithSFX
;> PlaySelectedMusic()
	call PlaySelectedMusic

;> DrawTwoObjects()
.draw
	call DrawTwoObjects
;> return
	ret

;=@u1
.up
	cp $1e
	jr c, .draw

;=@u2
	sub $02
	jr .set

;=@r1
.right
	cp $1d
	jr z, .draw

	cp $1f
	jr z, .draw

;=@r2
	inc a
	jr .set

;=@l1
.left
	cp $1c
	jr z, .draw

	cp $1e
	jr z, .draw

;=@l2
	dec a
	jr .set

;=@tp
.back
	push af
	ldh a, [hTwoPlayer]
	and a
	jr z, .toGameType

;=@b
	pop af
	jr .directions

;=@gt
.toGameType
	pop af
	ld a, $0e
;=@rd
	jr ConfirmGameMenu.setState

;@ def PlaySelectedMusic()
;@ path: screens/menus
;@ Starts the song chosen on the music menu (hMusicType $1C-$1E), or stops
;@ the music for "off" ($1F).
;@ reads: hMusicType
;@ writes: wMusicRequest
;@ test: hMusicType = rand(0x1C, 0x1F)
;@ sig: 99114681
PlaySelectedMusic::
;> song = u8(hMusicType - 0x17)
	ldh a, [hMusicType]
	sub $17
;> if song == 8:
	cp $08
	jr nz, .play

;>     song = 0xFF                                  # $FF: stop
	ld a, $ff

;> wMusicRequest = song
.play
	ld [wMusicRequest], a
;> return
	ret


;@ def State0E_GameTypeMenu()
;@ path: screens/menus
;@ Game state $0E: choosing A-TYPE or B-TYPE with Left/Right. A moves on to
;@ the music, Start confirms everything.
;@ reads: hGameType
;@ writes: hGameType, wSFXRequest, hGameState
;@ test: hJoyPressed = rng.choice([0, BTN_START, BTN_A, BTN_RIGHT, BTN_LEFT, BTN_UP])
;@ test: hTimer1 = rng.choice([0, 3])
;@ test: hGameType = rng.choice([GAME_TYPE_A, GAME_TYPE_B])
;@ test: for i in range(2): mem[0xC200 + 16 * i] = rng.choice([0, 0x80])
;@ test: for i in range(2): mem[0xC203 + 16 * i] = rand(0x1C, 0x1F)
;@ test: hObjHidden = 0
;@ sig: 29acd02b
State0E_GameTypeMenu::
;> buttons = BlinkObject(addr(wObjects) + 0x10)     # the game type cursor blinks
	ld de, wObjects + $10
	call BlinkObject
;> game_type = hGameType
	ld hl, hGameType
	ld a, [hl]
;> if buttons & BTN_START: return ConfirmGameMenu(addr(wObjects) + 0x10)
	bit 3, b
	jr nz, ConfirmGameMenu

;> if buttons & BTN_A:                              # on to the music
	bit 0, b
	jr nz, GameTypeMenuA
;>@a1     hGameState = 0x0F                            # (GameTypeMenuA, then ConfirmGameMenu's shared tail)
;>@a2     wObjects[0x10] = 0                           # stop blinking
;>@a3     return RedrawMenuCursors()

;> if buttons & BTN_RIGHT:
	inc e
	inc e
	bit 4, b
	jr nz, .right

;>@rc     if game_type == GAME_TYPE_B: return RedrawMenuCursors()
;>@rn     new = GAME_TYPE_B
;>@rl     label = 0x1D                                 # sprite $1D: "B-TYPE"
;> elif not (buttons & BTN_LEFT): return RedrawMenuCursors()
	bit 5, b
	jr z, RedrawMenuCursors

;> else:
;>     if game_type == GAME_TYPE_A: return RedrawMenuCursors()
	cp GAME_TYPE_A
	jr z, RedrawMenuCursors

;>     new = GAME_TYPE_A
	ld a, GAME_TYPE_A
;>     label = 0x1C                                 # sprite $1C: "A-TYPE"
	ld b, $1c
	jr .set

;=@rc
.right
	cp GAME_TYPE_B
	jr z, RedrawMenuCursors

;=@rn
	ld a, GAME_TYPE_B
;=@rl
	ld b, $1d

;> hGameType = new
.set
	ld [hl], a
;> wSFXRequest = 1
	push af
	ld a, $01
	ld [wSFXRequest], a
	pop af
;> wObjects[0x12] = new                             # the cursor X is the game type itself
	ld [de], a
	inc de
;> wObjects[0x13] = label
	ld a, b

.storeCursor:
	ld [de], a
;> RedrawMenuCursors()                              # falls through

;@ def RedrawMenuCursors()
;@ path: screens/menus
;@ Draws the two menu cursors (DrawTwoObjects). Shared tail of the menu states.
;@ test: for i in range(2): mem[0xC200 + 16 * i] = rng.choice([0, 0x80])
;@ test: for i in range(2): mem[0xC203 + 16 * i] = rand(0x1C, 0x1F)
;@ test: hObjHidden = 0
;@ sig: d1361290
RedrawMenuCursors::
;> DrawTwoObjects()
	call DrawTwoObjects
	ret


;@ def ConfirmGameMenu(cursor: de)
;@ path: screens/menus
;@ Start on the game/music menu: plays a sound and goes to the level select
;@ of the chosen game type. The cursor object stops blinking.
;@ reads: hGameType
;@ writes: wSFXRequest, hGameState
;@ test: cursor = rng.choice([0xC200, 0xC210])
;@ test: hGameType = rng.choice([GAME_TYPE_A, GAME_TYPE_B])
;@ test: for i in range(2): mem[0xC200 + 16 * i] = rng.choice([0, 0x80])
;@ test: for i in range(2): mem[0xC203 + 16 * i] = rand(0x1C, 0x1F)
;@ test: hObjHidden = 0
;@ sig: d1289160
ConfirmGameMenu::
;> wSFXRequest = 2
	ld a, $02
	ld [wSFXRequest], a
;> if hGameType == GAME_TYPE_A:
	ldh a, [hGameType]
	cp GAME_TYPE_A
;>     state = 0x10                                 # level select A
	ld a, $10
	jr z, .setState

;> else:
;>     state = 0x12                                 # level select B
	ld a, $12

;> hGameState = state
.setState:
	ldh [hGameState], a
;> mem[cursor] = 0                                  # stop blinking
;> RedrawMenuCursors()
	xor a
	jr State0E_GameTypeMenu.storeCursor

;=@State0E_GameTypeMenu.a1
GameTypeMenuA:
	ld a, $0f
	jr ConfirmGameMenu.setState

;@ def State10_TypeALevelInit()
;@ path: screens/level_select
;@ Game state $10: builds the type A level select with its top-3 table.
;@ reads: hTypeALevel, hNameEntryPending
;@ writes: hGameState
;@ test: skip switches the LCD off
;@ sig: 80f2cfc9
State10_TypeALevelInit::
;> DisableLCD()
	call DisableLCD
;> LoadScreen(TypeALevelSelectTilemap)
	ld de, TypeALevelSelectTilemap
	call LoadScreen
;> ClearHighScoreArea()
	call ClearHighScoreArea
;> ClearShadowOAM()
	call ClearShadowOAM
;> SetupObjects(wObjects, TypeALevelMenuObjects, 1)
	ld hl, wObjects
	ld de, TypeALevelMenuObjects
	ld c, $01
	call SetupObjects
;> SetupObjectWithSFX(hTypeALevel, TypeALevelPositions, addr(wObjects) + 1)   # cursor: digit sprite
	ld de, wObjects + $01
	ldh a, [hTypeALevel]
	ld hl, TypeALevelPositions
	call SetupObjectWithSFX
;> DrawTwoObjects()
	call DrawTwoObjects
;> ShowTypeAHighScores()
	call ShowTypeAHighScores
;> CopyHighScoresToVRAM()
	call CopyHighScoresToVRAM
;> rLCDC = 0xD3
	ld a, $d3
	ldh [rLCDC], a
;> hGameState = 0x11                                # State11_TypeALevelSelect
	ld a, $11
	ldh [hGameState], a
;> if hNameEntryPending:
	ldh a, [hNameEntryPending]
	and a
	jr nz, .state15

;>@s15     hGameState = 0x15
;>@ret     return
;> PlaySelectedMusic()
	call PlaySelectedMusic
;> return
	ret

;=@s15
.state15
	ld a, $15

.setState:
	ldh [hGameState], a
;=@ret
	ret


;@ def State11_TypeALevelSelect()
;@ path: screens/level_select
;@ Game state $11: choosing the type A level (0-9, a 5x2 grid). Start/A starts
;@ the game, B goes back to the game menu.
;@ reads: hTypeALevel
;@ writes: hTypeALevel, hGameState
;@ test: hJoyPressed = rng.choice([0, BTN_START, BTN_A, BTN_B, BTN_RIGHT, BTN_LEFT, BTN_UP, BTN_DOWN])
;@ test: hTimer1 = rng.choice([0, 3])
;@ test: hTypeALevel = rand(0, 9)
;@ test: fill_bcd(0xC0A0, 3)
;@ test: for i in range(2): mem[0xC200 + 16 * i] = rng.choice([0, 0x80]); mem[0xC203 + 16 * i] = rand(0x20, 0x29)
;@ test: hObjHidden = 0
;@ sig: 8ef8f6a1
State11_TypeALevelSelect::
;> buttons = BlinkObject(addr(wObjects))
	ld de, wObjects
	call BlinkObject
;=@lv
	ld hl, hTypeALevel
;> if buttons & BTN_START:                          # start the game
;>     hGameState = 0x0A
;>     return
	ld a, $0a
	bit 3, b
	jr nz, State10_TypeALevelInit.setState

;> if buttons & BTN_A:
;>     hGameState = 0x0A
;>     return
	bit 0, b
	jr nz, State10_TypeALevelInit.setState

;> if buttons & BTN_B:                              # back to the game menu
;>     hGameState = 0x08
;>     return
	ld a, $08
	bit 1, b
	jr nz, State10_TypeALevelInit.setState

;>@lv level = hTypeALevel
	ld a, [hl]
;> if buttons & BTN_RIGHT:
	bit 4, b
	jr nz, .right

;>@r1     if level == 9: return DrawTwoObjects()
;>@r2     new = level + 1
;> elif buttons & BTN_LEFT:
	bit 5, b
	jr nz, .left

;>@l1     if level == 0: return DrawTwoObjects()
;>@l2     new = level - 1
;> elif buttons & BTN_UP:
	bit 6, b
	jr nz, .up

;>@u1     if level < 5: return DrawTwoObjects()
;>@u2     new = level - 5
;> elif not (buttons & BTN_DOWN): return DrawTwoObjects()
	bit 7, b
	jr z, .draw

;> else:
;>     if level >= 5: return DrawTwoObjects()
	cp $05
	jr nc, .draw

;>     new = level + 5
	add $05
	jr .set

;=@r1
.right
	cp $09
	jr z, .draw

;=@r2
	inc a

;> hTypeALevel = new
.set
	ld [hl], a
;> SetupObjectWithSFX(new, TypeALevelPositions, addr(wObjects) + 1)
	ld de, wObjects + $01
	ld hl, TypeALevelPositions
	call SetupObjectWithSFX
;> ShowTypeAHighScores()
	call ShowTypeAHighScores

;> DrawTwoObjects()
.draw
	call DrawTwoObjects
;> return
	ret

;=@l1
.left
	and a
	jr z, .draw

;=@l2
	dec a
	jr .set

;=@u1
.up
	cp $05
	jr c, .draw

;=@u2
	sub $05
	jr .set

; (y, x) of the type A level cursor for levels 0-9
TypeALevelPositions::
	db $40, $30, $40, $40, $40, $50, $40, $60, $40, $70, $50, $30, $50, $40, $50, $50
	db $50, $60, $50, $70

;@ def State12_TypeBLevelInit()
;@ path: screens/level_select
;@ Game state $12: builds the type B level select (level and height cursors)
;@ with its top-3 table.
;@ reads: hTypeBLevel, hTypeBHigh, hNameEntryPending
;@ writes: hGameState
;@ test: skip switches the LCD off
;@ sig: ef1db1ac
State12_TypeBLevelInit::
;> DisableLCD()
	call DisableLCD
;> LoadScreen(TypeBLevelSelectTilemap)
	ld de, TypeBLevelSelectTilemap
	call LoadScreen
;> ClearShadowOAM()
	call ClearShadowOAM
;> SetupObjects(wObjects, TypeBLevelMenuObjects, 2)
	ld hl, wObjects
	ld de, TypeBLevelMenuObjects
	ld c, $02
	call SetupObjects
;> SetupObjectWithSFX(hTypeBLevel, TypeBLevelPositions, addr(wObjects) + 0x01)
	ld de, wObjects + $01
	ldh a, [hTypeBLevel]
	ld hl, TypeBLevelPositions
	call SetupObjectWithSFX
;> SetupObjectWithSFX(hTypeBHigh, TypeBHighPositions, addr(wObjects) + 0x11)
	ld de, wObjects + $11
	ldh a, [hTypeBHigh]
	ld hl, TypeBHighPositions
	call SetupObjectWithSFX
;> DrawTwoObjects()
	call DrawTwoObjects
;> ShowTypeBHighScores()
	call ShowTypeBHighScores
;> CopyHighScoresToVRAM()
	call CopyHighScoresToVRAM
;> rLCDC = 0xD3
	ld a, $d3
	ldh [rLCDC], a
;> hGameState = 0x13                                # State13_TypeBLevelSelect
	ld a, $13
	ldh [hGameState], a
;> if hNameEntryPending:
	ldh a, [hNameEntryPending]
	and a
	jr nz, .state15

;>@s15     hGameState = 0x15
;>@ret     return
;> PlaySelectedMusic()
	call PlaySelectedMusic
;> return
	ret

;=@s15
.state15
	ld a, $15
	ldh [hGameState], a
;=@ret
	ret

; shared tail of State13: set the state, stop the cursor blinking
;=@State13_TypeBLevelSelect.s2
TypeBLevelSetState:
	ldh [hGameState], a
;=@State13_TypeBLevelSelect.s3
	xor a
	ld [de], a
;=@State13_TypeBLevelSelect.s4
	ret


;@ def State13_TypeBLevelSelect()
;@ path: screens/level_select
;@ Game state $13: choosing the type B level (0-9). Start starts the game,
;@ A moves on to the height, B goes back to the game menu.
;@ reads: hTypeBLevel
;@ writes: hTypeBLevel, hGameState
;@ test: hJoyPressed = rng.choice([0, BTN_START, BTN_A, BTN_B, BTN_RIGHT, BTN_LEFT, BTN_UP, BTN_DOWN])
;@ test: hTimer1 = rng.choice([0, 3])
;@ test: hTypeBLevel = rand(0, 9)
;@ test: hTypeBHigh = rand(0, 5)
;@ test: fill_bcd(0xC0A0, 3)
;@ test: for i in range(2): mem[0xC200 + 16 * i] = rng.choice([0, 0x80]); mem[0xC203 + 16 * i] = rand(0x20, 0x29)
;@ test: hObjHidden = 0
;@ sig: fff661d0
State13_TypeBLevelSelect::
;> buttons = BlinkObject(addr(wObjects))
	ld de, wObjects
	call BlinkObject
;=@lv
	ld hl, hTypeBLevel
;>@s1 if buttons & BTN_START:                          # start the game
;>@s2     hGameState = 0x0A                            # (stored in TypeBLevelSetState, shared by the 3 exits)
;>@s3     wObjects[0] = 0                              # stop blinking
;>@s4     return
;=@s2
	ld a, $0a
;=@s1
	bit 3, b
	jr nz, TypeBLevelSetState

;> if buttons & BTN_A:                              # on to the height
;>     hGameState = 0x14
;>     wObjects[0] = 0
;>     return
	ld a, $14
	bit 0, b
	jr nz, TypeBLevelSetState

;> if buttons & BTN_B:                              # back to the game menu
;>     hGameState = 0x08
;>     wObjects[0] = 0
;>     return
	ld a, $08
	bit 1, b
	jr nz, TypeBLevelSetState

;>@lv level = hTypeBLevel
	ld a, [hl]
;> if buttons & BTN_RIGHT:
	bit 4, b
	jr nz, .right

;>@r1     if level == 9: return DrawTwoObjects()
;>@r2     new = level + 1
;> elif buttons & BTN_LEFT:
	bit 5, b
	jr nz, .left

;>@l1     if level == 0: return DrawTwoObjects()
;>@l2     new = level - 1
;> elif buttons & BTN_UP:
	bit 6, b
	jr nz, .up

;>@u1     if level < 5: return DrawTwoObjects()
;>@u2     new = level - 5
;> elif not (buttons & BTN_DOWN): return DrawTwoObjects()
	bit 7, b
	jr z, .draw

;> else:
;>     if level >= 5: return DrawTwoObjects()
	cp $05
	jr nc, .draw

;>     new = level + 5
	add $05
	jr .set

;=@r1
.right
	cp $09
	jr z, .draw

;=@r2
	inc a

;> hTypeBLevel = new
.set
	ld [hl], a
;> SetupObjectWithSFX(new, TypeBLevelPositions, addr(wObjects) + 1)
	ld de, wObjects + $01
	ld hl, TypeBLevelPositions
	call SetupObjectWithSFX
;> ShowTypeBHighScores()
	call ShowTypeBHighScores

;> DrawTwoObjects()
.draw
	call DrawTwoObjects
;> return
	ret

;=@l1
.left
	and a
	jr z, .draw

;=@l2
	dec a
	jr .set

;=@u1
.up
	cp $05
	jr c, .draw

;=@u2
	sub $05
	jr .set

; (y, x) of the type B level cursor for levels 0-9
TypeBLevelPositions::
	db $40, $18, $40, $28, $40, $38, $40, $48, $40, $58, $50, $18, $50, $28, $50, $38
	db $50, $48, $50, $58

;@ def SetStateStopBlink(state: a, blink: de)
;@ path: screens/level_select
;@ Shared tail of State14_TypeBHighSelect: switch to `state` and clear the
;@ blinking object's state byte.
;@ writes: hGameState
;@ test: state = rand(0, 0x30)
;@ test: blink = rand_ram(1)
;@ sig: c85d0605
SetStateStopBlink::
;> hGameState = state
;> mem[blink] = 0
	ldh [hGameState], a
	xor a
	ld [de], a
	ret


;@ def State14_TypeBHighSelect()
;@ path: screens/level_select
;@ Game state $14: choosing the type B height (0-5, a 3x2 grid). Start/A
;@ starts the game, B goes back to the level.
;@ reads: hTypeBHigh
;@ writes: hTypeBHigh, hGameState
;@ test: hJoyPressed = rng.choice([0, BTN_START, BTN_A, BTN_B, BTN_RIGHT, BTN_LEFT, BTN_UP, BTN_DOWN])
;@ test: hTimer1 = rng.choice([0, 3])
;@ test: hTypeBLevel = rand(0, 9)
;@ test: hTypeBHigh = rand(0, 5)
;@ test: fill_bcd(0xC0A0, 3)
;@ test: for i in range(2): mem[0xC200 + 16 * i] = rng.choice([0, 0x80]); mem[0xC203 + 16 * i] = rand(0x20, 0x29)
;@ test: hObjHidden = 0
;@ sig: 7dd1dea8
State14_TypeBHighSelect::
;> buttons = BlinkObject(addr(wObjects) + 0x10)
	ld de, wObjects + $10
	call BlinkObject
;=@hi
	ld hl, hTypeBHigh
;> if buttons & BTN_START: return SetStateStopBlink(0x0A, addr(wObjects) + 0x10)   # start the game
	ld a, $0a
	bit 3, b
	jr nz, SetStateStopBlink

;> if buttons & BTN_A: return SetStateStopBlink(0x0A, addr(wObjects) + 0x10)
	bit 0, b
	jr nz, SetStateStopBlink

;> if buttons & BTN_B: return SetStateStopBlink(0x13, addr(wObjects) + 0x10)       # back to the level
	ld a, $13
	bit 1, b
	jr nz, SetStateStopBlink

;>@hi high = hTypeBHigh
	ld a, [hl]
;> if buttons & BTN_RIGHT:
	bit 4, b
	jr nz, .right

;>@r1     if high == 5: return DrawTwoObjects()
;>@r2     new = high + 1
;> elif buttons & BTN_LEFT:
	bit 5, b
	jr nz, .left

;>@l1     if high == 0: return DrawTwoObjects()
;>@l2     new = high - 1
;> elif buttons & BTN_UP:
	bit 6, b
	jr nz, .up

;>@u1     if high < 3: return DrawTwoObjects()
;>@u2     new = high - 3
;> elif not (buttons & BTN_DOWN): return DrawTwoObjects()
	bit 7, b
	jr z, .draw

;> else:
;>     if high >= 3: return DrawTwoObjects()
	cp $03
	jr nc, .draw

;>     new = high + 3
	add $03
	jr .set

;=@r1
.right
	cp $05
	jr z, .draw

;=@r2
	inc a

;> hTypeBHigh = new
.set
	ld [hl], a
;> SetupObjectWithSFX(new, TypeBHighPositions, addr(wObjects) + 0x11)
	ld de, wObjects + $11
	ld hl, TypeBHighPositions
	call SetupObjectWithSFX
;> ShowTypeBHighScores()
	call ShowTypeBHighScores

;> DrawTwoObjects()
.draw
	call DrawTwoObjects
;> return
	ret

;=@l1
.left
	and a
	jr z, .draw

;=@l2
	dec a
	jr .set

;=@u1
.up
	cp $03
	jr c, .draw

;=@u2
	sub $03
	jr .set

; (y, x) of the type B height cursor for heights 0-5, then an unused byte
TypeBHighPositions::
	db $40, $70, $40, $80, $40, $90, $50, $70, $50, $80, $50, $90, $00

;@ def SetupObjectWithSFX(index: a, table: hl, dest: de) -> de
;@ path: gfx/objects
;@ Plays sound effect 1, then does SetupObjectFromTable.
;@ writes: wSFXRequest
;@ test: index = rand(0, 15)
;@ test: table = rand(0x0000, 0x7000)
;@ test: dest = rand_ram(3)
;@ sig: 7400efcb
SetupObjectWithSFX::
;> wSFXRequest = 1
	push af
	ld a, $01
	ld [wSFXRequest], a
	pop af
;> return SetupObjectFromTable(index, table, dest)  # falls through

;@ def SetupObjectFromTable(index: a, table: hl, dest: de) -> de
;@ path: gfx/objects
;@ Copies entry `index` (2 bytes) of table to dest and writes index + $20
;@ after it - e.g. an object's y, x and sprite id. Returns dest + 2.
;@ clobbers: a, bc, hl
;@ test: index = rand(0, 255)
;@ test: table = rand(0x0000, 0x7000)
;@ test: dest = rand_ram(3)
;@ sig: 23eac6be
SetupObjectFromTable::
;> offset = u8(2 * index)
	push af
	add a
;> entry = table + offset
	ld c, a
	ld b, $00
	add hl, bc
;> mem[dest] = mem[entry]
	ld a, [hli]
	ld [de], a
;> dest += 1
	inc de
;> mem[dest] = mem[entry + 1]
	ld a, [hl]
	ld [de], a
;> dest += 1
	inc de
;> mem[dest] = u8(index + 0x20)
	pop af
	add $20
	ld [de], a
;> return dest
	ret


;@ def BlinkObject(obj: de) -> b
;@ path: gfx/objects
;@ Every 16 frames (timed with hTimer1) toggles bit 7 of the byte at obj -
;@ an object's state byte - so the object blinks. Returns hJoyPressed.
;@ reads: hJoyPressed, hTimer1
;@ writes: hTimer1
;@ test: obj = rand_ram(1)
;@ test: hTimer1 = rng.choice([0, 0, 5])
;@ sig: a0a05c3b
BlinkObject::
;> buttons = hJoyPressed
	ldh a, [hJoyPressed]
	ld b, a
;> if hTimer1 == 0:
	ldh a, [hTimer1]
	and a
	ret nz

;>     hTimer1 = 16
	ld a, $10
	ldh [hTimer1], a
;>     mem[obj] ^= 0x80
	ld a, [de]
	xor $80
	ld [de], a
;> return buttons
	ret


;@ def SetupObjects(dest: hl, src: de, count: c)
;@ path: gfx/objects
;@ Copies `count` 6-byte object records from src into the 16-byte object
;@ slots at dest, and marks the slot after them hidden ($80). Only the low
;@ byte of the slot address moves, so the slots must lie in one 256-byte page.
;@ clobbers: a, b, c, de, hl
;@ test: dest = 0xC200
;@ test: count = rand(1, 15)
;@ test: src = rand(0x0000, 0x7000)
;@ sig: da6aaf32
SetupObjects::
;>@obj for _ in range(count):
;>@byte     for i in range(6):
	push hl
	ld b, $06

;>         mem[dest + i] = mem[src]
.copy
	ld a, [de]
	ld [hli], a
;>         src += 1
	inc de
;=@byte
	dec b
	jr nz, .copy

;>     dest = (dest & 0xFF00) | lo(dest + 16)        # next slot
	pop hl
	ld a, $10
	add l
	ld l, a
;=@obj
	dec c
	jr nz, SetupObjects

;> mem[dest] = 0x80
	ld [hl], $80
;> return
	ret


;@ def ClearShadowOAM()
;@ path: gfx/objects
;@ Clears all 40 sprite entries of the shadow OAM.
;@ clobbers: a, b, hl
;@ sig: 47d4ea7c
ClearShadowOAM::
;>@loop for i in range(160):
	xor a
	ld hl, wShadowOAM
	ld b, $a0

;>     mem[wShadowOAM + i] = 0
.loop
	ld [hli], a
;=@loop
	dec b
	jr nz, .loop

;> return
	ret


;@ def ShowTypeAHighScores()
;@ path: screens/high_scores
;@ Draws the top-3 table of the selected type A level (via UpdateHighScores).
;@ reads: hTypeALevel
;@ test: hTypeALevel = rand(0, 9)
;@ test: fill_bcd(0xC0A0, 3)
;@ sig: 870980cf
ShowTypeAHighScores::
;> ClearHighScoreArea()
	call ClearHighScoreArea
;> n = hTypeALevel
	ldh a, [hTypeALevel]
;> entry = wTypeAHighScores
	ld hl, wTypeAHighScores
;=@add
	ld de, $001b

;>@find while n:                                    # entry = wTypeAHighScores + 27 * hTypeALevel
.find
	and a
	jr z, .found

;>     n -= 1
	dec a
;>@add     entry += 27
	add hl, de
;=@find
	jr .find

;> entry += 2                                       # top byte of the first score
.found
	inc hl
	inc hl
;> UpdateHighScores(entry)
	push hl
	pop de
	call UpdateHighScores
;> return
	ret


;@ def ShowTypeBHighScores()
;@ path: screens/high_scores
;@ Draws the top-3 table of the selected type B level and height (via UpdateHighScores).
;@ reads: hTypeBLevel, hTypeBHigh
;@ test: hTypeBLevel = rand(0, 9)
;@ test: hTypeBHigh = rand(0, 5)
;@ test: fill_bcd(0xC0A0, 3)
;@ sig: b1eacae9
ShowTypeBHighScores::
;> ClearHighScoreArea()
	call ClearHighScoreArea
;> n = hTypeBLevel
	ldh a, [hTypeBLevel]
;> entry = wTypeBHighScores
	ld hl, wTypeBHighScores
;=@addl
	ld de, $00a2

;>@level while n:                                   # entry += 6 * 27 * hTypeBLevel
.findLevel
	and a
	jr z, .findHigh

;>     n -= 1
	dec a
;>@addl     entry += 6 * 27
	add hl, de
;=@level
	jr .findLevel

;> n = hTypeBHigh
.findHigh
	ldh a, [hTypeBHigh]
;=@addh
	ld de, $001b

;>@high while n:                                    # entry += 27 * hTypeBHigh
.loop
	and a
	jr z, .found

;>     n -= 1
	dec a
;>@addh     entry += 27
	add hl, de
;=@high
	jr .loop

;> entry += 2                                       # top byte of the first score
.found
	inc hl
	inc hl
;> UpdateHighScores(entry)
	push hl
	pop de
	call UpdateHighScores
;> return
	ret


;@ def DrawScoreDigits(src: hl, dest: de)
;@ path: gfx/numbers
;@ Draws a 3-byte BCD score (most significant byte at src, the others below)
;@ as 6 digit tiles at dest. Leading zeros leave their cells untouched.
;@ clobbers: a, b, e, hl
;@ test: src = rand_ram(3) + 2
;@ test: fill_bcd(src - 2, 3)
;@ test: dest = rand(0xC800, 0xC8F0)
;@ sig: 95eca2a8
DrawScoreDigits::
;> n = 3
	ld b, $03

;>@lead while True:                                 # skip leading zeros
;>     if mem[src] >> 4:
;>         skip_high = False
;>         break
.leading
	ld a, [hl]
	and $f0
	jr nz, .digits

;>     dest = (dest & 0xFF00) | lo(dest + 1)
	inc e
;>     low = mem[src] & 0x0F
;>     src -= 1
	ld a, [hld]
	and $0f
;>     if low:
;>         skip_high = True
;>         break
	jr nz, .low

;>     dest = (dest & 0xFF00) | lo(dest + 1)
	inc e
;>     n -= 1
	dec b
;>     if n == 0: return                            # all zero: nothing drawn
	jr nz, .leading

	ret

;>@dig while True:
;>     if not skip_high:
;>         mem[dest] = mem[src] >> 4
.digits
	ld a, [hl]
	and $f0
	swap a
	ld [de], a
;>         dest = (dest & 0xFF00) | lo(dest + 1)
	inc e
;>         low = mem[src] & 0x0F
;>         src -= 1
	ld a, [hld]
	and $0f

;>     skip_high = False
;>     mem[dest] = low
.low
	ld [de], a
;>     dest = (dest & 0xFF00) | lo(dest + 1)
	inc e
;>     n -= 1
	dec b
;>     if n == 0: return
	jr nz, .digits

	ret


;@ def CopyBackward3(src: hl, dest: de)
;@ path: lib/memory
;@ CopyBackward of 3 bytes.
;@ test: src = rand_ram(4) + 3
;@ test: dest = rand_ram(4) + 3
;@ sig: 8e8ae4c3
CopyBackward3::
;> CopyBackward(src, dest, 3)                       # falls through
	ld b, $03

;@ def CopyBackward(src: hl, dest: de, count: b)
;@ path: lib/memory
;@ Copies `count` bytes going down in memory: src, src - 1, ... to dest, dest - 1, ...
;@ clobbers: a, b, de, hl
;@ test: src = rand_ram(8) + 8
;@ test: dest = rand_ram(8) + 8
;@ test: count = rand(1, 8)
;@ sig: cb29e590
CopyBackward::
;>@loop for _ in range(count):
;>     mem[dest] = mem[src]
;>     src -= 1
	ld a, [hld]
	ld [de], a
;>     dest -= 1
	dec de
;=@loop
	dec b
	jr nz, CopyBackward

;> return
	ret


;@ def UpdateHighScores(entry: de)
;@ path: screens/high_scores
;@ Puts the score into a top-3 table if it is good enough - lower entries
;@ and names move down, the new name starts as "A....." and name entry is
;@ armed (hNameEntryPending) - then draws the table into wBGMap0Copy and
;@ clears the score data. `entry` points at the top byte of the first score;
;@ a table entry is 3 scores (3 bytes each) followed by 3 names (6 bytes each).
;@ reads: wScore
;@ writes: hSpawnBlocked, hPrevPieceRoll, hNameRank, hMessagePosHi, hMessagePosLo, hClearAnimPhase, hDemoCountdown, wMusicRequest, hNameEntryPending, hHighScoresDirty
;@ test: entry = 0xD002 + 27 * rand(0, 69)
;@ test: fill_bcd(0xC0A0, 3)
;@ test: for i in range(3): fill_bcd(entry - 2 + 3 * i, 3)
;@ sig: c415330f
UpdateHighScores::
;> pos = entry
;> hSpawnBlocked = hi(entry)                        # (borrowed as scratch)
	ld a, d
	ldh [hSpawnBlocked], a
;> hPrevPieceRoll = lo(entry)
	ld a, e
	ldh [hPrevPieceRoll], a
;>@rank for rank in range(3):                       # find the first score below wScore
	ld c, $03

;>     q = addr(wScore) + 2                         # compare from the top byte down
.compare
	ld hl, wScore + 2
;>     p = pos
	push de
;>@byte     for _ in range(3):
	ld b, $03

;>         d = mem[p] - mem[q]
.compareByte
	ld a, [de]
	sub [hl]
;>         if d < 0: break
	jr c, .insert

;>         if d > 0: break
	jr nz, .lower

;>         q -= 1
	dec l
;>         p -= 1
	dec de
;=@byte
	dec b
	jr nz, .compareByte

;>@lower     if d < 0: break                        # wScore is bigger: insert it here
;>     pos += 3
.lower
	pop de
	inc de
	inc de
	inc de
;=@rank
	dec c
	jr nz, .compare

;> else:
;>     rank = None
;>@ins if rank is not None:
	jr .draw

;=@lower
.insert
	pop de
;>     pos = hSpawnBlocked << 8 | hPrevPieceRoll    # back to entry
	ldh a, [hSpawnBlocked]
	ld d, a
	ldh a, [hPrevPieceRoll]
	ld e, a
	push de
;>     dst = pos + 6                                # top byte of the last score
	push bc
	ld hl, $0006
	add hl, de
	push hl
	pop de
;>     src = dst - 3
	dec hl
	dec hl
	dec hl

;>@mvs     for _ in range(2 - rank):                 # lower scores move down one place
.moveScores
	dec c
	jr z, .storeScore

;>         copy(dst - 2, src - 2, 3)
;>         dst, src = src, src - 3
	call CopyBackward3
;=@mvs
	jr .moveScores

;>     src = addr(wScore) + 2                       # the new score
.storeScore
	ld hl, wScore + 2
;>@cps     for _ in range(3):
	ld b, $03

;>         mem[dst] = mem[src]
;>         src -= 1
.copyScore
	ld a, [hld]
	ld [de], a
;>         dst = (dst & 0xFF00) | lo(dst - 1)
	dec e
;=@cps
	dec b
	jr nz, .copyScore

;>     hNameRank = 3 - rank
	pop bc
	pop de
	ld a, c
	ldh [hNameRank], a
;>     src = pos + 18                               # last byte of the second name
	ld hl, $0012
	add hl, de
	push hl
;>     dst = src + 6                                # last byte of the third name
	ld de, $0006
	add hl, de
	push hl
	pop de
	pop hl

;>@mvn     for _ in range(2 - rank):                 # and so do their names
.moveNames
	dec c
	jr z, .newName

;>         copy(dst - 5, src - 5, 6)
;>         dst, src = src, src - 6
	ld b, $06
	call CopyBackward
;=@mvn
	jr .moveNames

;>@dots     for _ in range(5):                       # "....."
.newName
	ld a, $60
	ld b, $05

;>         mem[dst] = 0x60
.dots
	ld [de], a
;>         dst -= 1
	dec de
;=@dots
	dec b
	jr nz, .dots

;>     mem[dst] = 0x0A                              # "A"
	ld a, $0a
	ld [de], a
;>     hMessagePosHi = hi(dst)                      # name entry edits it here
	ld a, d
	ldh [hMessagePosHi], a
;>     hMessagePosLo = lo(dst)
	ld a, e
	ldh [hMessagePosLo], a
;>     hClearAnimPhase = 0                          # (borrowed: blink flag, cursor)
	xor a
	ldh [hClearAnimPhase], a
;>     hDemoCountdown = 0
	ldh [hDemoCountdown], a
;>     wMusicRequest = 1
	ld a, $01
	ld [wMusicRequest], a
;>     hNameEntryPending = 1
	ldh [hNameEntryPending], a

;> dst = wBGMap0Copy + 0x1AC
.draw
	ld de, wBGMap0Copy + $1AC
;> src = hSpawnBlocked << 8 | hPrevPieceRoll        # = entry
	ldh a, [hSpawnBlocked]
	ld h, a
	ldh a, [hPrevPieceRoll]
	ld l, a
;>@drs for row in range(3):
	ld b, $03

;>     DrawScoreDigits(src, dst)
.drawScore
	push hl
	push de
	push bc
	call DrawScoreDigits
	pop bc
	pop de
;>     dst += 32
	ld hl, $0020
	add hl, de
	push hl
	pop de
;>     src += 3
	pop hl
	push de
	ld de, $0003
	add hl, de
	pop de
;=@drs
	dec b
	jr nz, .drawScore

;> src -= 2                                         # the first name
	dec hl
	dec hl
;>@dst dst = wBGMap0Copy + 0x1A4
;>@drn for row in range(3):                         # names: up to 6 letters, a 0 ends one early
	ld b, $03
;=@dst
	ld de, wBGMap0Copy + $1A4

;>     row_start = dst
.drawName
	push de
;>@let     for i in range(6):
	ld c, $06

;>         ch = mem[src]
;>         src += 1
.letter
	ld a, [hli]
;>         if ch == 0: break
	and a
	jr z, .nextName

;>         mem[dst] = ch
	ld [de], a
;>         dst += 1
	inc de
;=@let
	dec c
	jr nz, .letter

;>     dst = row_start
.nextName
	pop de
;>     dst += 32
	push hl
	ld hl, $0020
	add hl, de
	push hl
	pop de
	pop hl
;=@drn
	dec b
	jr nz, .drawName

;> ClearScoreData()
	call ClearScoreData
;> hHighScoresDirty = 1
	ld a, $01
	ldh [hHighScoresDirty], a
;> return
	ret


;@ def CopyHighScoresToVRAM()
;@ path: screens/high_scores
;@ Called from VBlank: if hHighScoresDirty is set, copies the top-3 area
;@ (3 rows, two 6-tile columns: scores and names) from wBGMap0Copy to BG map 0.
;@ reads: hHighScoresDirty
;@ writes: hHighScoresDirty
;@ clobbers: a, bc, de, hl
;@ test: hHighScoresDirty = rng.choice([0, 1])
;@ sig: ad2f0a6f
CopyHighScoresToVRAM::
;> if not hHighScoresDirty: return
	ldh a, [hHighScoresDirty]
	and a
	ret z

;> dst = vBGMap0 + 0x1A4
	ld hl, vBGMap0 + $1A4
;> src = wBGMap0Copy + 0x1A4
	ld de, wBGMap0Copy + $1A4
;>@row for row in range(3):
	ld c, $06

;>     line = dst
.row
	push hl

;>@half     for half in range(2):                       # scores, then names
;>@col         for col in range(6):
.half
	ld b, $06

;>             mem[dst] = mem[src]
.copy
	ld a, [de]
	ld [hli], a
;>             dst, src = dst + 1, src + 1
	inc e
;=@col
	dec b
	jr nz, .copy

;>         dst, src = dst + 2, src + 2                  # skip the gap
	inc e
	inc l
	inc e
	inc l
;=@row
	dec c
	jr z, .done

;=@half
	bit 0, c
	jr nz, .half

;>     dst = line + 32
	pop hl
	ld de, $0020
	add hl, de
;>     src = dst + (wBGMap0Copy - vBGMap0)
	push hl
	pop de
	ld a, HIGH(wBGMap0Copy - vBGMap0)
	add d
	ld d, a
;=@row
	jr .row

.done
	pop hl
;> hHighScoresDirty = 0
	xor a
	ldh [hHighScoresDirty], a
;> return
	ret


;@ def ClearHighScoreArea()
;@ path: screens/high_scores
;@ Fills the top-3 area of wBGMap0Copy (3 rows of 14 tiles) with tile $60.
;@ clobbers: a, bc, de, hl
;@ sig: d3b987ca
ClearHighScoreArea::
;> p = wBGMap0Copy + 0x1A4
	ld hl, wBGMap0Copy + $1A4
	ld de, $0020
;> tile = 0x60
	ld a, $60
;>@row for row in range(3):
	ld c, $03

;>     fill(p, tile, 14)
.row
	ld b, $0e
	push hl

.loop
	ld [hli], a
	dec b
	jr nz, .loop

;>     p += 32
	pop hl
	add hl, de
;=@row
	dec c
	jr nz, .row

;> return
	ret


;@ def State15_NameEntry()
;@ path: screens/high_scores
;@ Game state $15: entering a name for a new high score, right in the table
;@ (hMessagePosHi:Lo points at the letter). Up/Down change the letter
;@ (A-Z, a few symbols, blank; the heart only in hard mode) with autoshift,
;@ A goes to the next letter, B back, Start finishes. The letter blinks.
;@ reads: hNameRank, hDemoCountdown, hMessagePosHi, hMessagePosLo, hTimer1, hClearAnimPhase, hJoyPressed, hJoyHeld, hAutoShiftTimer, hHardMode, hGameType
;@ writes: hTimer1, hClearAnimPhase, hAutoShiftTimer, wSFXRequest, hDemoCountdown, hMessagePosHi, hMessagePosLo, hNameEntryPending, hGameState
;@ test: skip waits for the LCD
;@ sig: 6d542523
State15_NameEntry::
;> cell = vBGMap0 + 0x1E4                           # the letter on screen
	ldh a, [hNameRank]
	ld hl, vBGMap0 + $1E4
	ld de, -32

;>@row for _ in range(hNameRank - 1):
.row
	dec a
	jr z, .column

;>     cell -= 32
	add hl, de
;=@row
	jr .row

;> cell += hDemoCountdown                           # (hDemoCountdown: cursor)
.column
	ldh a, [hDemoCountdown]
	ld e, a
	ld d, $00
	add hl, de
;> p = hMessagePosHi << 8 | hMessagePosLo           # the letter, in the table
	ldh a, [hMessagePosHi]
	ld d, a
	ldh a, [hMessagePosLo]
	ld e, a
;> if not hTimer1:                                  # blink
	ldh a, [hTimer1]
	and a
	jr nz, .buttons

;>     hTimer1 = 7
	ld a, $07
	ldh [hTimer1], a
;>     hClearAnimPhase ^= 1
	ldh a, [hClearAnimPhase]
	xor $01
	ldh [hClearAnimPhase], a
;>     WriteTileA(TILE_BLANK if hClearAnimPhase else mem[p], cell)
	ld a, [de]
	jr z, .blink

	ld a, TILE_BLANK

.blink
	call WriteTileA

;> pressed = hJoyPressed
.buttons
	ldh a, [hJoyPressed]
	ld b, a
;> held = hJoyHeld
	ldh a, [hJoyHeld]
	ld c, a
;> timer = 23                                       # autoshift delay after a fresh press
	ld a, $17
;> if (pressed | held) & BTN_UP:
	bit 6, b
	jr nz, .up

	bit 6, c
	jr nz, .upHeld

;>@uh     if not pressed & BTN_UP:
;>@uhd         hAutoShiftTimer -= 1
;>@uhr         if hAutoShiftTimer: return
;>@uh9         timer = 9
;>@uts     hAutoShiftTimer = timer
;>@ul     last = 0x27 if hHardMode else 0x26           # the heart only in hard mode
;>@uc     c = mem[p]
;>@ueq     if c == last:
;>@ublk         c = TILE_BLANK
;>@unb     elif c == TILE_BLANK:
;>@ua         c = 0x0A
;>@uel     else:
;>@uinc         c += 1
;> elif (pressed | held) & BTN_DOWN:
	bit 7, b
	jr nz, .down

	bit 7, c
	jr nz, .downHeld

;>@dh     if not pressed & BTN_DOWN:
;>@dhd         hAutoShiftTimer -= 1
;>@dhr         if hAutoShiftTimer: return
;>@dh9         timer = 9
;>@dts     hAutoShiftTimer = timer
;>@dl     last = 0x27 if hHardMode else 0x26
;>@dc     c = mem[p]
;>@deq     if c == 0x0A:
;>@dblk         c = TILE_BLANK
;>@dnb     elif c == TILE_BLANK:
;>@dlast         c = last
;>@del     else:
;>@ddec         c -= 1
;> else:
;>     if pressed & BTN_A:                          # next letter
	bit 0, b
	jr nz, .nextLetter

;>@aw         WriteTileA(mem[p], cell)
;>@asfx         wSFXRequest = 2
;>@a6         if hDemoCountdown + 1 != 6:              # (after the sixth letter: finish, as with Start)
;>@ainc             hDemoCountdown += 1
;>@ap             p += 1
;>@a60             if mem[p] == 0x60:
;>@aa                 mem[p] = 0x0A
;>@apos             hMessagePosHi = hi(p)
;>@aplo             hMessagePosLo = lo(p)
;>@aret             return
;>     elif pressed & BTN_B:                        # one letter back
	bit 1, b
	jp nz, .back

;>@b0         if not hDemoCountdown: return
;>@bw         WriteTileA(mem[p], cell)
;>@bdec         hDemoCountdown -= 1
;>@bp         p -= 1
;>@bpos         hMessagePosHi = hi(p)
;>@bplo         hMessagePosLo = lo(p)
;>@bret         return
;>     elif not pressed & BTN_START: return
	bit 3, b
	ret z

;>     WriteTileA(mem[p], cell)                     # finish
.finish
	ld a, [de]
	call WriteTileA
;>     PlaySelectedMusic()
	call PlaySelectedMusic
;>     hNameEntryPending = 0
	xor a
	ldh [hNameEntryPending], a
;>     hGameState = 0x11 if hGameType == GAME_TYPE_A else 0x13
	ldh a, [hGameType]
	cp GAME_TYPE_A
	ld a, $11
	jr z, .setState

	ld a, $13

.setState
	ldh [hGameState], a
;>     return
	ret

;>@st mem[p] = c
;>@sfx wSFXRequest = 1
;>@ret return
;=@uhd
.upHeld
	ldh a, [hAutoShiftTimer]
	dec a
	ldh [hAutoShiftTimer], a
;=@uhr
	ret nz

;=@uh9
	ld a, $09

;=@uts
.up
	ldh [hAutoShiftTimer], a
;=@ul
	ld b, $26
	ldh a, [hHardMode]
	and a
	jr z, .upLetter

	ld b, $27

;=@uc
.upLetter
	ld a, [de]
;=@ueq
	cp b
	jr nz, .notLast

;=@ublk
	ld a, $2e

;=@uinc
.increment
	inc a

;=@st
.storeLetter
	ld [de], a
;=@sfx
	ld a, $01
	ld [wSFXRequest], a
;=@ret
	ret

;=@unb
.notLast
	cp TILE_BLANK
	jr nz, .increment

;=@ua
	ld a, $0a
	jr .storeLetter

;=@dhd
.downHeld
	ldh a, [hAutoShiftTimer]
	dec a
	ldh [hAutoShiftTimer], a
;=@dhr
	ret nz

;=@dh9
	ld a, $09

;=@dts
.down
	ldh [hAutoShiftTimer], a
;=@dl
	ld b, $26
	ldh a, [hHardMode]
	and a
	jr z, .downLetter

	ld b, $27

;=@dc
.downLetter
	ld a, [de]
;=@deq
	cp $0a
	jr nz, .notFirst

;=@dblk
	ld a, $30

;=@ddec
.decrement
	dec a
	jr .storeLetter

;=@dnb
.notFirst
	cp TILE_BLANK
	jr nz, .decrement

;=@dlast
	ld a, b
	jr .storeLetter

;=@aw
.nextLetter
	ld a, [de]
	call WriteTileA
;=@asfx
	ld a, $02
	ld [wSFXRequest], a
;=@a6
	ldh a, [hDemoCountdown]
	inc a
	cp $06
	jr z, .finish

;=@ainc
	ldh [hDemoCountdown], a
;=@ap
	inc de
;=@a60
	ld a, [de]
	cp $60
	jr nz, .storePos

;=@aa
	ld a, $0a
	ld [de], a

;=@apos
.storePos
	ld a, d
	ldh [hMessagePosHi], a
;=@aplo
	ld a, e
	ldh [hMessagePosLo], a
;=@aret
	ret

;=@b0
.back
	ldh a, [hDemoCountdown]
	and a
	ret z

;=@bw
	ld a, [de]
	call WriteTileA
;=@bdec
	ldh a, [hDemoCountdown]
	dec a
	ldh [hDemoCountdown], a
;=@bp
	dec de
;=@bpos
	jr .storePos



;@ def WriteTileA(tile: a, dest: hl)
;@ path: gfx/tilemaps
;@ WriteTileB with the tile in a.
;@ test: skip waits for the LCD
;@ sig: 3aba3bbe
WriteTileA::
;> WriteTileB(tile, dest)                           # falls through
	ld b, a

;@ def WriteTileB(tile: b, dest: hl)
;@ path: gfx/tilemaps
;@ Waits for HBlank, then writes a tile to VRAM.
;@ test: skip waits for the LCD
;@ sig: 2a6e6d7b
WriteTileB::
;> wait_hblank()
	ldh a, [rSTAT]
	and $03
	jr nz, WriteTileB

;> mem[dest] = tile
	ld [hl], b
;> return
	ret


;@ def State0A_StartGame()
;@ path: game/setup
;@ Game state $0A: sets up a new game - board, screens (BG map 1 doubles as
;@ the pause screen), level, line counter, the first pieces and for type B
;@ the garbage - then switches to state 0.
;@ writes: hBoardCopyStage, hClearAnimPhase, hCollision, hFallDelay, hGameState, hLevel, hLevelDigitPos, hLines, hPiecePhase, hSpawnBlocked, hTemp, wObjects
;@ reads: hDemo, hGameType, hHardMode, hLevel, hLevelDigitPos, hTypeBHigh, wPreviewHidden
;@ test: skip switches the LCD off
;@ sig: 3c4c36b5
State0A_StartGame::
;> DisableLCD()
	call DisableLCD
;> wObjects[0x10] = 0
	xor a
	ld [wObjects + $10], a
;> hPiecePhase = 0
	ldh [hPiecePhase], a
;> hClearAnimPhase = 0
	ldh [hClearAnimPhase], a
;> hCollision = 0
	ldh [hCollision], a
;> hSpawnBlocked = 0
	ldh [hSpawnBlocked], a
;> hLines = lo(hLines)
	ldh [hLines + 1], a
;> FillBoardAndRefresh(TILE_BLANK)
	ld a, TILE_BLANK
	call FillBoardAndRefresh
;> ClearHiddenRows()
	call ClearHiddenRows
;> ClearScoreData()
	call ClearScoreData
;> hBoardCopyStage = 0
	xor a
	ldh [hBoardCopyStage], a
;> ClearShadowOAM()
	call ClearShadowOAM
;>@if if hGameType == GAME_TYPE_B:
	ldh a, [hGameType]
;>@sb     screen = GameScreenTypeB
	ld de, GameScreenTypeB
;>@lb     level = hTypeBLevel
	ld hl, hTypeBLevel
;=@if
	cp GAME_TYPE_B
;>@pb     digit_pos = 0x50
	ld a, $50
;=@if
	jr z, .setLevel

;> else:
;>     digit_pos = 0xF1
	ld a, $f1
;>     level = hTypeALevel
	ld hl, hTypeALevel
;>     screen = GameScreenTypeA
	ld de, GameScreenTypeA

;> hLevelDigitPos = digit_pos
.setLevel
	push de
	ldh [hLevelDigitPos], a
;> hLevel = level
	ld a, [hl]
	ldh [hLevel], a
;> LoadScreen(screen)
	call LoadScreen
;> LoadScreenAt(screen, vBGMap1)                   # the same screen on BG map 1 ...
	pop de
	ld hl, vBGMap1
	call LoadScreenAt
;> CopyTilemap8Wide(vBGMap1 + 0x63, PauseScreenText, 10)   # ... with the pause text on the board
	ld de, PauseScreenText
	ld hl, vBGMap1 + $63
	ld c, $0a
	call CopyTilemap8Wide
;> mem[vBGMap0 | hLevelDigitPos] = hLevel           # level digit, both maps
	ld h, HIGH(vBGMap0)
	ldh a, [hLevelDigitPos]
	ld l, a
	ldh a, [hLevel]
	ld [hl], a
;> mem[vBGMap1 | hLevelDigitPos] = hLevel
	ld h, HIGH(vBGMap1)
	ld [hl], a
;> if hHardMode:                                    # a heart next to the level
	ldh a, [hHardMode]
	and a
	jr z, .objects

;>     mem[(vBGMap1 | hLevelDigitPos) + 1] = 0x27
	inc hl
	ld [hl], $27
;>     mem[(vBGMap0 | hLevelDigitPos) + 1] = 0x27
	ld h, HIGH(vBGMap0)
	ld [hl], $27

;> CopyUntilFF(wObjects, FallingPieceTemplate)
.objects
	ld hl, wObjects
	ld de, FallingPieceTemplate
	call CopyUntilFF
;> CopyUntilFF(addr(wObjects) + 0x10, NextPieceTemplate)
	ld hl, wObjects + $10
	ld de, NextPieceTemplate
	call CopyUntilFF
;> p = vBGMap0 + 0x151                              # the lines counter on screen
	ld hl, vBGMap0 + $151
;> lines = 0x25 if hGameType == GAME_TYPE_B else 0      # type B: clear 25 lines
	ldh a, [hGameType]
	cp GAME_TYPE_B
	ld a, $25
	jr z, .setLines

	xor a

;> hLines = lines
.setLines
	ldh [hLines], a
;> mem[p] = lines & 0x0F
	and $0f
	ld [hld], a
;> if lines & 0x0F:
	jr z, .speed

;>     mem[p - 1] = 2
	ld [hl], $02

;> SetFallSpeed()
.speed
	call SetFallSpeed
;> if wPreviewHidden:
	ld a, [wPreviewHidden]
	and a
	jr z, .spawn

;>     wObjects[0x10] = 0x80
	ld a, $80
	ld [wObjects + $10], a

;> SpawnNextPiece()                                 # fill the randomizer's look-ahead
.spawn
	call SpawnNextPiece
;> SpawnNextPiece()
	call SpawnNextPiece
;> SpawnNextPiece()
	call SpawnNextPiece
;> DrawObject0()
	call DrawObject0
;> hTemp = 0
	xor a
	ldh [hTemp], a
;> if hGameType == GAME_TYPE_B:
	ldh a, [hGameType]
	cp GAME_TYPE_B
	jr nz, .done

;>     hFallDelay = 0x34
	ld a, $34
	ldh [hFallDelay], a
;>     mem[vBGMap0 + 0xB0] = hTypeBHigh
	ldh a, [hTypeBHigh]
	ld hl, vBGMap0 + $B0
	ld [hl], a
;>     mem[vBGMap1 + 0xB0] = hTypeBHigh
	ld h, HIGH(vBGMap1)
	ld [hl], a
;>     if hTypeBHigh:
	and a
	jr z, .done

;>         if hDemo:
	ld b, a
	ldh a, [hDemo]
	and a
	jr z, .randomGarbage

;>             DrawDemoGarbage()
	call DrawDemoGarbage
;>         else:
	jr .done

;>             GenerateGarbage(hTypeBHigh, vBGMap0 + 0x202, 0xFFC0)   # $FFC0 = -64: two rows up per height
.randomGarbage
	ld a, b
	ld de, hGameType
	ld hl, vBGMap0 + $202
	call GenerateGarbage

;> rLCDC = 0xD3
.done
	ld a, $d3
	ldh [rLCDC], a
;> hGameState = 0                                  # State00_Playing
	xor a
	ldh [hGameState], a
;> return
	ret


;@ def SetFallSpeed()
;@ path: game/setup
;@ Sets the fall speed for the current level - in hard mode for level + 10,
;@ but never faster than level 20.
;@ reads: hLevel, hHardMode
;@ writes: hFallDelay, hFallDelayBase
;@ clobbers: a, de, hl
;@ test: hLevel = rand(0, 20)
;@ test: hHardMode = rng.choice([0, 1])
;@ sig: 9f87471a
SetFallSpeed::
;> speed_level = hLevel
	ldh a, [hLevel]
	ld e, a
;> if hHardMode:
	ldh a, [hHardMode]
	and a
	jr z, .lookup

;>     speed_level += 10
	ld a, $0a
	add e
;>     if speed_level > 20:                         # never faster than level 20
	cp $15
	jr c, .capped

;>         speed_level = 20
	ld a, $14

.capped
	ld e, a

;> delay = mem[FallDelayTable + speed_level]
.lookup
	ld hl, FallDelayTable
	ld d, $00
	add hl, de
	ld a, [hl]
;> hFallDelay = delay
	ldh [hFallDelay], a
;> hFallDelayBase = delay
	ldh [hFallDelayBase], a
;> return
	ret
FallDelayTable::
	db $34, $30, $2c, $28, $24, $20, $1b, $15, $10, $0a, $09, $08, $07, $06, $05, $05
	db $04, $04, $03, $03, $02

;@ def DrawDemoGarbage()
;@ path: game/setup
;@ Draws the fixed garbage of the type B demo (4 rows) on BG map 0 and into wBGMap0Copy.
;@ clobbers: a, bc, de, hl
;@ sig: b9146c7d
DrawDemoGarbage::
;> p = vBGMap0 + 0x1C2
	ld hl, vBGMap0 + $1C2
;> src = DemoGarbage
	ld de, DemoGarbage
;>@row for row in range(4):
	ld c, $04

;>@line     line = p
;>@x     for x in range(10):
.row
	ld b, $0a
;=@line
	push hl

;>         mem[p] = mem[src]
.loop
	ld a, [de]
	ld [hl], a
;>         q = p + (wBGMap0Copy - vBGMap0)
	push hl
	ld a, h
	add HIGH(wBGMap0Copy - vBGMap0)
	ld h, a
;>         mem[q] = mem[src]
	ld a, [de]
	ld [hl], a
	pop hl
;>         p += 1
	inc l
;>         src += 1
	inc de
;=@x
	dec b
	jr nz, .loop

;>     p = line + 32
	pop hl
	push de
	ld de, $0020
	add hl, de
	pop de
;=@row
	dec c
	jr nz, .row

;> return
	ret

;@ asset: tilemap width=10 height=4 tiles=LoadGameTiles
;@ The fixed garbage of the type B demo.
DemoGarbage::
	db $85, $2f, $82, $86, $83, $2f, $2f, $80, $82, $85, $2f, $82, $84, $82, $83, $2f
	db $83, $2f, $87, $2f, $2f, $85, $2f, $83, $2f, $86, $82, $80, $81, $2f, $83, $2f
	db $86, $83, $2f, $85, $2f, $85, $2f, $2f

;@ def GenerateGarbage(height: a, start: hl, step: de)
;@ path: game/setup
;@ Type B: fills the bottom 2 * height board rows with random blocks (on BG
;@ map 0 and, in a 1-player game, in wBGMap0Copy). rDIV is the random source;
;@ every row is guaranteed at least one hole.
;@ reads: rDIV, hTwoPlayer
;@ writes: hTemp
;@ clobbers: a, b, de, hl
;@ test: height = rand(1, 5)
;@ test: start = 0x9A02
;@ test: step = 0xFFC0
;@ test: hTwoPlayer = rng.choice([0, 1])
;@ sig: f6139d14
GenerateGarbage::
;> pos = start
;>@top for _ in range(u8(height - 1)):              # find the top garbage row
	ld b, a

.findTop
	dec b
	jr z, .cell

;>     pos = u16(pos + step)
	add hl, de
;=@top
	jr .findTop

;>@cell while True:
;>     n = rDIV
.cell
	ldh a, [rDIV]
	ld b, a

;>     tile = 0x80
.flip
	ld a, $80

;>@flip     for _ in range(u8(n - 1)):                  # flip between $80 and blank: blank if n is even
.count
	dec b
	jr z, .chosen

;>         if tile == 0x80:
	cp $80
	jr nz, .flip

;>             tile = TILE_BLANK
	ld a, TILE_BLANK
;=@flip
	jr .count

;>         else:
;>             tile = 0x80
;>     if tile != TILE_BLANK:
.chosen
	cp TILE_BLANK
	jr z, .hole

;>         tile = (rDIV & 7) | 0x80                 # random block tile $80-$87
	ldh a, [rDIV]
	and $07
	or $80
;>     else:
	jr .place

;>         hTemp = TILE_BLANK                       # this row has its hole
.hole
	ldh [hTemp], a

;>@last     if lo(pos) & 0x0F == 0x0B:                  # last cell of the row
.place
	push af
	ld a, l
	and $0f
	cp $0b
	jr nz, .keep

;>         if hTemp != TILE_BLANK:                  # no hole yet: force one
	ldh a, [hTemp]
	cp TILE_BLANK
	jr z, .keep

;>             tile = TILE_BLANK
	pop af
	ld a, TILE_BLANK
	jr .write

;=@last
.keep
	pop af

;>     mem[pos] = tile
.write
	ld [hl], a
;>     if not hTwoPlayer:
	push hl
	push af
	ldh a, [hTwoPlayer]
	and a
	jr nz, .writeAgain

;>         mem[pos + 0x3000] = tile                 # also into wBGMap0Copy
	ld de, wBGMap0Copy - vBGMap0
	add hl, de

.writeAgain
	pop af
	ld [hl], a
	pop hl
;>     pos += 1
	inc hl
;>     if lo(pos) & 0x0F == 0x0C:                    # end of the row
	ld a, l
	and $0f
	cp $0c
	jr nz, .cell

;>         hTemp = 0
	xor a
	ldh [hTemp], a
;>         if hi(pos) & 0x0F == 0x0A:
	ld a, h
	and $0f
	cp $0a
	jr z, .lastRow

;>@bottom             if lo(pos) == 0x2C:                  # past the bottom row
;>@ret                 return
;>         pos += 0x16
.nextRow
	ld de, $0016
	add hl, de
;=@cell
	jr .cell

;=@bottom
.lastRow
	ld a, l
	cp $2c
	jr nz, .nextRow

;=@ret
	ret


;@ def State00_Playing()
;@ path: game/loop
;@ Game state $00: one frame of a running game.
;@ reads: hPaused, wPreviewHidden
;@ writes: wObjects, wPreviewHidden
;@ test: skip runs the whole game frame (link cable, LCD waits)
;@ sig: e5eb9e68
State00_Playing::
;> HandlePause()
	call HandlePause
;> if hPaused: return
	ldh a, [hPaused]
	and a
	ret nz

;> DemoCheckEnd()
	call DemoCheckEnd
;> DemoPlayback()                                   # replaces the input during a demo
	call DemoPlayback
;> DemoRecord()
	call DemoRecord
;> HandlePieceInput()                               # rotate, move left/right
	call HandlePieceInput
;> UpdateFall()                                     # gravity, soft drop, landing
	call UpdateFall
;> CheckLines()                                     # phase 2: find full rows
	call CheckLines
;> LockPiece()                                      # phase 1: piece into the board
	call LockPiece
;> CollapseClearedRows()
	call CollapseClearedRows
;> AwardLineClearPoints()
	call AwardLineClearPoints
;> DemoRestoreInput()
	call DemoRestoreInput
;> return
	ret

; Select during the game (from HandlePause): toggle the next piece preview
;=@HandlePause.sel
TogglePreview:
	bit 2, a
	ret z

;=@HandlePause.flip
	ld a, [wPreviewHidden]
	xor $01
	ld [wPreviewHidden], a
;=@HandlePause.if2
	jr z, .show

;=@HandlePause.hide
	ld a, $80

.setPreview
	ld [wObjects + $10], a
;=@HandlePause.draw
	call DrawObject1
;=@HandlePause.selret
	ret

;=@HandlePause.show
.show
	xor a
	jr .setPreview

;@ def HandlePause()
;@ path: game/loop
;@ A+B+Select+Start resets the game; Start pauses/unpauses (BG map 1, which
;@ holds the pause screen, is shown while paused); Select toggles the next
;@ piece preview. In a 2-player game only the master can pause.
;@ reads: hJoyHeld, hJoyPressed, hDemo, hTwoPlayer, hSerialRole, hSerialRx, hSerialTx, wPreviewHidden
;@ writes: hPaused, rLCDC, wSoundPause, wPreviewHidden, hPausedSerialRx, hPausedSerialTx, wObjects
;@ test: skip waits for the LCD, talks to the link cable
;@ sig: f3d36f8a
HandlePause::
;> if (hJoyHeld & 0x0F) == 0x0F: goto(SoftReset)
	ldh a, [hJoyHeld]
	and $0f
	cp $0f
	jp z, SoftReset

;> if hDemo: return
	ldh a, [hDemo]
	and a
	ret nz

;> if not hJoyPressed & BTN_START:
	ldh a, [hJoyPressed]
	bit 3, a
	jr z, TogglePreview

;>@sel     if hJoyPressed & BTN_SELECT:                 # (TogglePreview, at the end of State00_Playing)
;>@flip         wPreviewHidden ^= 1
;>@if2         if wPreviewHidden:
;>@hide             wObjects[0x10] = 0x80
;>@else2         else:
;>@show             wObjects[0x10] = 0
;>@draw         DrawObject1()
;>@selret     return
;> if hTwoPlayer:
	ldh a, [hTwoPlayer]
	and a
	jr nz, .twoPlayer

;>@master     if hSerialRole != SERIAL_MASTER: return
;>@toggle2     hPaused ^= 1
;>@resume     if not hPaused: goto(UpdateLinkPause.resume)            # resume (in UpdateLinkPause)
;>@sound2     wSoundPause = 1
;>@rx     hPausedSerialRx = hSerialRx
;>@tx     hPausedSerialTx = hSerialTx
;>@text     DrawPauseText()
;>@ret2     return
;> hPaused ^= 1
	ld hl, rLCDC
	ldh a, [hPaused]
	xor $01
	ldh [hPaused], a
;> if hPaused:
	jr z, .unpause

;>     rLCDC |= 0x08                                # show BG map 1: the pause screen
	set 3, [hl]
;>     wSoundPause = 1
	ld a, $01
	ld [wSoundPause], a
;>@copy     for i in range(4):                           # copy the line counter onto it
	ld hl, vBGMap0 + $14E
	ld de, vBGMap1 + $14E
	ld b, $04

;>         wait_hblank()
.copyLines
	ldh a, [rSTAT]
	and $03
	jr nz, .copyLines

;>         mem[vBGMap1 + 0x14E + i] = mem[vBGMap0 + 0x14E + i]
	ld a, [hli]
	ld [de], a
	inc de
;=@copy
	dec b
	jr nz, .copyLines

;>     wObjects[0x10] = 0x80                        # hide both pieces
	ld a, $80

.setNext
	ld [wObjects + $10], a

;>     wObjects[0] = 0x80
.setPiece
	ld [wObjects], a
;=@draw0
	call DrawObject0
;=@draw1
	call DrawObject1
;=@ret
	ret

;> else:
;>     rLCDC &= ~0x08
.unpause
	res 3, [hl]
;>     wSoundPause = 2
	ld a, $02
	ld [wSoundPause], a
;>     if not wPreviewHidden:
	ld a, [wPreviewHidden]
	and a
	jr z, .setNext

;>         wObjects[0x10] = 0
;>     wObjects[0] = 0
	xor a
	jr .setPiece

;>@draw0 DrawObject0()
;>@draw1 DrawObject1()
;>@ret return
;=@master
.twoPlayer
	ldh a, [hSerialRole]
	cp SERIAL_MASTER
	ret nz

;=@toggle2
	ldh a, [hPaused]
	xor $01
	ldh [hPaused], a
;=@resume
	jr z, UpdateLinkPause.resume

;=@sound2
	ld a, $01
	ld [wSoundPause], a
;=@rx
	ldh a, [hSerialRx]
	ldh [hPausedSerialRx], a
;=@tx
	ldh a, [hSerialTx]
	ldh [hPausedSerialTx], a
;=@text
	call DrawPauseText
;=@ret2
	ret


;@ def UpdateLinkPause()
;@ path: game/loop
;@ 2-player game while paused: keeps both Game Boys in step. The master sends
;@ $94 ("still paused"); the slave unpauses when that stops. While paused it
;@ also ends the caller's frame early (it drops the caller's return address).
;@ Note: the `jr z` after reading hSerialDone tests the flags of the earlier
;@ `and a`, so the transfer-done check never skips anything.
;@ reads: hPaused, hSerialRole, hSerialRx, hPausedSerialRx, hPausedSerialTx
;@ writes: hSerialDone, hSerialTx, hSerialSendPending, hSerialRx, wSoundPause, hPaused
;@ test: skip talks to the link cable and manipulates the stack
;@ sig: db394783
UpdateLinkPause::
;> if not hPaused: return
	ldh a, [hPaused]
	and a
	ret z

;> hSerialDone = 0                                  # (the jr z before it is never taken)
	ldh a, [hSerialDone]
	jr z, .stillPaused

	xor a
	ldh [hSerialDone], a
;> if hSerialRole == SERIAL_MASTER:
	ldh a, [hSerialRole]
	cp SERIAL_MASTER
	jr nz, .slave

;>     hSerialTx = 0x94
	ld a, $94
	ldh [hSerialTx], a
;>     hSerialSendPending = 0x94
	ldh [hSerialSendPending], a
;>     return_from_caller()                         # pop hl / ret: the caller's frame ends here
	pop hl
	ret

;> hSerialTx = 0
.slave
	xor a
	ldh [hSerialTx], a
;> if hSerialRx == 0x94:
	ldh a, [hSerialRx]
	cp $94
	jr z, .stillPaused

;>@still     return_from_caller()                         # the master is still paused
;> # resume (also reached from HandlePause)
;> hSerialRx = hPausedSerialRx
.resume:
	ldh a, [hPausedSerialRx]
	ldh [hSerialRx], a
;> hSerialTx = hPausedSerialTx
	ldh a, [hPausedSerialTx]
	ldh [hSerialTx], a
;> wSoundPause = 2
	ld a, $02
	ld [wSoundPause], a
;> hPaused = 0
	xor a
	ldh [hPaused], a
;> dst = vBGMap0 + 0xEE
	ld hl, vBGMap0 + $EE
;> tile = TILE_WALL
	ld b, TILE_WALL
;>@erase for _ in range(5):
	ld c, $05

;>     WriteTileB(tile, dst)                         # paint over "PAUSE"
.erase
	call WriteTileB
;>     dst += 1
	inc l
;=@erase
	dec c
	jr nz, .erase

;> return
	ret

;=@still
.stillPaused:
	pop hl
	ret


;@ def DrawPauseText()
;@ path: game/loop
;@ Writes "PAUSE" onto the board (BG map 0), waiting for HBlank per tile.
;@ test: skip waits for the LCD
;@ sig: 618789b8
DrawPauseText::
;> dst = vBGMap0 + 0xEE
	ld hl, vBGMap0 + $EE
;>@src src = PauseText
;>@loop for _ in range(5):
	ld c, $05
;=@src
	ld de, PauseText

;>     WriteTileA(mem[src], dst)
.loop
	ld a, [de]
	call WriteTileA
;>     src += 1
	inc de
;>     dst += 1
	inc l
;=@loop
	dec c
	jr nz, .loop

;> return
	ret
PauseText::
	db $19, $0a, $1e, $1c, $0e

;@ def State01_GameOver()
;@ path: game/game_over
;@ Game state $01 (the stack reached the top): hides the pieces and starts
;@ filling the board with tile $87 - the board refresh draws it row by row.
;@ writes: wObjects, hPiecePhase, hClearAnimPhase, hTimer1, hGameState
;@ test: mem[0xC203] = rand(0, 27)
;@ test: mem[0xC213] = rand(0, 27)
;@ test: hObjHidden = 0
;@ sig: aa0ee5da
State01_GameOver::
;> wObjects[0] = 0x80
	ld a, $80
	ld [wObjects], a
;> wObjects[0x10] = 0x80
	ld [wObjects + $10], a
;> DrawObject0()
	call DrawObject0
;> DrawObject1()
	call DrawObject1
;> hPiecePhase = 0
	xor a
	ldh [hPiecePhase], a
;> hClearAnimPhase = 0
	ldh [hClearAnimPhase], a
;> ClearClearedRows()
	call ClearClearedRows
;> FillBoardAndRefresh(0x87)
	ld a, $87
	call FillBoardAndRefresh
;> hTimer1 = 70
	ld a, $46
	ldh [hTimer1], a
;> hGameState = 0x0D                                # State0D_GameOverScreen
	ld a, $0d
	ldh [hGameState], a
;> return
	ret


;@ def State04_GameOverWait()
;@ path: game/game_over
;@ Game state $04: waits for A or Start, then back to the level select of the
;@ game type (or to state $16 in a 2-player game).
;@ reads: hJoyPressed, hTwoPlayer, hGameType
;@ writes: hBoardCopyStage, hGameState
;@ test: hJoyPressed = rng.choice([0, BTN_A, BTN_START, BTN_B])
;@ test: hTwoPlayer = rng.choice([0, 0, 1])
;@ test: hGameType = rng.choice([GAME_TYPE_A, GAME_TYPE_B])
;@ sig: 242d890b
State04_GameOverWait::
;> if not hJoyPressed & BTN_A:
	ldh a, [hJoyPressed]
	bit 0, a
	jr nz, .next

;>     if not hJoyPressed & BTN_START: return
	bit 3, a
	ret z

;> hBoardCopyStage = 0
.next
	xor a
	ldh [hBoardCopyStage], a
;> if hTwoPlayer: state = 0x16
	ldh a, [hTwoPlayer]
	and a
	ld a, $16
	jr nz, .set

;> elif hGameType == GAME_TYPE_A: state = 0x10      # level select
	ldh a, [hGameType]
	cp GAME_TYPE_A
	ld a, $10
	jr z, .set

;> else: state = 0x12
	ld a, $12

;> hGameState = state
.set
	ldh [hGameState], a
;> return
	ret


;@ def State05_TypeBTally()
;@ path: game/tally
;@ Game state $05: the type B result screen. Draws the tally text into the
;@ board and, from level 1 on, the points per line clear at this level.
;@ reads: hTimer1, hTypeBLevel
;@ writes: wScore, hTimer1, wObjects, hLines, hGameState
;@ test: skip calls InitSound (sound engine)
;@ sig: 48e924e1
State05_TypeBTally::
;> if hTimer1: return
	ldh a, [hTimer1]
	and a
	ret nz

;> CopyTilemapBlock(TypeBTallyText, wBGMap0Copy + 0x002)
	ld hl, wBGMap0Copy + $002
	ld de, TypeBTallyText
	call CopyTilemapBlock
;> if hTypeBLevel:
	ldh a, [hTypeBLevel]
	and a
	jr z, .done

;>     DrawPointValue(0x0040, wBGMap0Copy + 0x027)  # points for a single at this level
	ld de, $0040
	ld hl, wBGMap0Copy + $027
	call DrawPointValue
;>     DrawPointValue(0x0100, wBGMap0Copy + 0x087)  # double
	ld de, $0100
	ld hl, wBGMap0Copy + $087
	call DrawPointValue
;>     DrawPointValue(0x0300, wBGMap0Copy + 0x0E7)  # triple
	ld de, $0300
	ld hl, wBGMap0Copy + $0e7
	call DrawPointValue
;>     DrawPointValue(0x1200, wBGMap0Copy + 0x147)  # tetris
	ld de, $1200
	ld hl, wBGMap0Copy + $147
	call DrawPointValue
;>@clr     for i in range(3):
	ld hl, wScore
	ld b, $03
	xor a

;>         mem[addr(wScore) + i] = 0
.clear
	ld [hli], a
;=@clr
	dec b
	jr nz, .clear

;> hTimer1 = 0x80
.done
	ld a, $80
	ldh [hTimer1], a
;> wObjects[0] = 0x80
	ld a, $80
	ld [wObjects], a
;> wObjects[0x10] = 0x80
	ld [wObjects + $10], a
;> DrawObject0()
	call DrawObject0
;> DrawObject1()
	call DrawObject1
;> InitSound()
	call InitSound
;> hLines = (hLines & 0xFF00) | 0x25
	ld a, $25
	ldh [hLines], a
;> hGameState = 0x0B                                # State0B_StartTally
	ld a, $0b
	ldh [hGameState], a
;> return
	ret


;@ def DrawPointValue(points: de, dest: hl)
;@ path: game/tally
;@ Draws points * (hTypeBLevel + 1) as digits at dest, without leading zeros.
;@ Uses wScore as the work area.
;@ reads: hTypeBLevel
;@ writes: wScore
;@ clobbers: a, b, de, hl
;@ test: points = rng.choice([0x0040, 0x0100, 0x0300, 0x1200])
;@ test: dest = rand_ram(6)
;@ test: hTypeBLevel = rand(0, 9)
;@ sig: 185b1f9d
DrawPointValue::
;>@clr for i in range(3):
;=@p
	push hl
;=@clr
	ld hl, wScore
	ld b, $03
	xor a

;>     mem[addr(wScore) + i] = 0
.clear
	ld [hli], a
;=@clr
	dec b
	jr nz, .clear

;>@add for _ in range(u8(hTypeBLevel + 1) or 256):
	ldh a, [hTypeBLevel]
	ld b, a
	inc b

;>     AddScoreBCD(points, addr(wScore))
.add
	ld hl, wScore
	call AddScoreBCD
;=@add
	dec b
	jr nz, .add

;>@p p = dest                                       # (kept on the stack meanwhile)
	pop hl
;> n = 3
	ld b, $03
;> src = addr(wScore) + 2                           # most significant byte first
	ld de, wScore + 2
;> high = True
;>@skip while True:                                 # skip the leading zeros
.skipZeros
;>     if mem[src] & 0xF0: break
	ld a, [de]
	and $f0
	jr nz, .high

;>     if mem[src] & 0x0F:
	ld a, [de]
	and $0f
	jr nz, .low

;>@lowonly         high = False                         # start with the low digit
;>@brk         break
;>     src -= 1
	dec e
;>     n -= 1
	dec b
;>     if not n: return
	jr nz, .skipZeros

	ret

;>@out while True:
;>@hi     if high:
;>         mem[p] = mem[src] >> 4
.high
	ld a, [de]
	and $f0
	swap a
	ld [hli], a

;>@p1         p += 1
;>@high     high = True
;>     mem[p] = mem[src] & 0x0F
.low
	ld a, [de]
	and $0f
	ld [hli], a
;>@p2     p += 1
;>     src -= 1
	dec e
;>     n -= 1
	dec b
;>     if not n: return
	jr nz, .high

	ret


;@ def State0B_StartTally()
;@ path: game/tally
;@ Game state $0B: whenever hTimer1 runs out, lets VBlank count the next
;@ step of the type B tally (UpdateTally).
;@ reads: hTimer1
;@ writes: wTallyStep, hTimer1
;@ test: hTimer1 = rng.choice([0, 3])
;@ sig: f12d89d2
State0B_StartTally::
;> if hTimer1: return
	ldh a, [hTimer1]
	and a
	ret nz

;> wTallyStep = 1
	ld a, $01
	ld [wTallyStep], a
;> hTimer1 = 5
	ld a, $05
	ldh [hTimer1], a
;> return
	ret


;@ def State22_DancersInit()
;@ path: endings/dancers
;@ Game state $22 (a type B game won at level 9): the dancers ending. Draws
;@ its board text and sets up 10 dancer objects; the higher the chosen
;@ height, the more of them dance (all 10 at height 5).
;@ reads: hTimer1, hTypeBHigh
;@ writes: wObjects, wMusicRequest, hLines, hTimer1, hGameState
;@ test: hTimer1 = rng.choice([0, 0, 5])
;@ test: hTypeBHigh = rand(0, 5)
;@ sig: 0ac1fcb5
State22_DancersInit::
;> if hTimer1: return
	ldh a, [hTimer1]
	and a
	ret nz

;> CopyTilemapBlock(DancersText, wBGMap0Copy + 0x002)
	ld hl, wBGMap0Copy + $002
	ld de, DancersText
	call CopyTilemapBlock
;> ClearShadowOAM()
	call ClearShadowOAM
;> SetupObjects(wObjects, DancerObjects, 10)        # all start hidden
	ld hl, wObjects
	ld de, DancerObjects
	ld c, $0a
	call SetupObjects
;> wObjects[0x66] = 0x10                            # dancers 6 and 7 use palette OBP1
	ld a, $10
	ld hl, wObjects + $66
	ld [hl], a
;> wObjects[0x76] = 0x10
	ld l, $76
	ld [hl], a
;> p = addr(wObjects) + 0x0E                        # animation timer and its reload value
	ld hl, wObjects + $0E
;> src = DancerAnimSpeeds
	ld de, DancerAnimSpeeds
;>@speeds for i in range(10):
	ld b, $0a

;>     mem[p] = mem[src]
.speeds
	ld a, [de]
	ld [hli], a
;>     mem[p + 1] = mem[src]
	ld [hli], a
;>     src += 1
	inc de
;>     p += 16
	push de
	ld de, $000e
	add hl, de
	pop de
;=@speeds
	dec b
	jr nz, .speeds

;> n = hTypeBHigh
	ldh a, [hTypeBHigh]
;> if n == 5:                                       # all 10 at height 5
	cp $05
	jr nz, .count

;>     n = 9
	ld a, $09

;> n += 1
.count
	inc a
;>@p p = addr(wObjects)
;>@show for _ in range(n):
	ld b, a
;=@p
	ld hl, wObjects
	ld de, $0010
;>     mem[p] = 0                                   # visible
	xor a

.show
	ld [hl], a
;>     p += 16
	add hl, de
;=@show
	dec b
	jr nz, .show

;> wMusicRequest = hTypeBHigh + 0x0A
	ldh a, [hTypeBHigh]
	add $0a
	ld [wMusicRequest], a
;> hLines = (hLines & 0xFF00) | 0x25
	ld a, $25
	ldh [hLines], a
;> hTimer1 = 0x1B
	ld a, $1b
	ldh [hTimer1], a
;> hGameState = 0x23                                # State23_Dancers
	ld a, $23
	ldh [hGameState], a
;> return
	ret

; Frames per animation step for each of the 10 dancers
DancerAnimSpeeds::
	db $1c, $0f, $1e, $32, $20, $18, $26, $1d, $28, $2b

;@ def DrawDancers()
;@ path: endings/dancers
;@ Shared tail of State23_Dancers: the 10 dancer objects to OAM.
;@ test: for i in range(10): mem[0xC200 + 16 * i] = rng.choice([0, 0x80]); mem[0xC203 + 16 * i] = rng.choice([0x44, 0x45, 0x50, 0x51])
;@ test: hObjHidden = 0
;@ sig: 36f4c63d
DrawDancers::
;> DrawObjectsAt0(10)
	ld a, $0a
	call DrawObjectsAt0
	ret


;@ def State23_Dancers()
;@ path: endings/dancers
;@ Game state $23: animates the dancers (each with its own speed) until the
;@ music ends, then the type B tally (state $05) - or after height 5, state $26.
;@ reads: hTimer1, wObjects, wCurrentSong, hTypeBHigh
;@ writes: wObjects, hGameState
;@ test: hTimer1 = rng.choice([0, 0, 20, 5])
;@ test: for i in range(10): mem[0xC200 + 16 * i] = rng.choice([0, 0x80]); mem[0xC203 + 16 * i] = rng.choice([0x44, 0x45, 0x50, 0x51]); mem[0xC20E + 16 * i] = rand(1, 3)
;@ test: wCurrentSong = rng.choice([0, 1])
;@ test: hTypeBHigh = rand(0, 5)
;@ test: hObjHidden = 0
;@ sig: cd933b55
State23_Dancers::
;> if hTimer1 == 20:
	ldh a, [hTimer1]
	cp $14
	jr z, DrawDancers

;>     DrawObjectsAt0(10)                           # (DrawDancers)
;>     return
;> if hTimer1: return
	and a
	ret nz

;> obj = addr(wObjects)
	ld hl, wObjects + $0E
	ld de, $0010
;>@dancer for i in range(10):
	ld b, $0a

;>     mem[obj + 0x0E] -= 1
.dancer
	push hl
	dec [hl]
;>     if mem[obj + 0x0E] == 0:
	jr nz, .next

;>         mem[obj + 0x0E] = mem[obj + 0x0F]       # reload the timer
	inc l
	ld a, [hld]
	ld [hl], a
;>         frame = obj + 3
	ld a, l
	and $f0
	or $03
	ld l, a
;>         mem[frame] ^= 1                          # next animation frame
	ld a, [hl]
	xor $01
	ld [hl], a
;>         if mem[frame] == 0x50:
	cp $50
	jr z, .frame50

;>@f50             mem[obj + 1] = 0x67
;>         elif mem[frame] == 0x51:
	cp $51
	jr z, .frame51

;>@f51             mem[obj + 1] = 0x5D
;>     obj += 16
.next
	pop hl
	add hl, de
;=@dancer
	dec b
	jr nz, .dancer

;> DrawObjectsAt0(10)
	ld a, $0a
	call DrawObjectsAt0
;> if wCurrentSong: return                          # dance until the music ends
	ld a, [wCurrentSong]
	and a
	ret nz

;> ClearShadowOAM()
	call ClearShadowOAM
;> if hTypeBHigh == 5: state = 0x26
	ldh a, [hTypeBHigh]
	cp $05
	ld a, $26
	jr z, .setState

;> else: state = 0x05
	ld a, $05

;> hGameState = state
.setState
	ldh [hGameState], a
;> return
	ret

;=@f50
.frame50
	dec l
	dec l
	ld [hl], $67
	jr .next

;=@f51
.frame51
	dec l
	dec l
	ld [hl], $5d
	jr .next

;@ def TallyDropPoints()
;@ path: game/tally
;@ Last tally row (from UpdateTally): one soft drop point at a time moves
;@ from the drop counter to the score.
;@ reads: wScoreTally
;@ writes: wTallyStep, wScoreTally, hTimer1, wScore, wSFXRequest
;@ test: mem[0xC0C0] = rng.choice([0, 1, 7]); mem[0xC0C1] = rng.choice([0, 0, 1])
;@ test: fill_bcd(0xC0C2, 3)
;@ test: fill_bcd(0xC0A0, 3)
;@ sig: 9523fc6f
TallyDropPoints::
;> wTallyStep = 0
	xor a
	ld [wTallyStep], a
;> p = addr(wScoreTally) + 20                       # the soft drop counter
	ld de, wScoreTally + 20
;> drops = mem16[p]
	ld a, [de]
	ld l, a
	inc de
	ld a, [de]
	ld h, a
;> if drops == 0: return TallyNextRow()
	or l
	jp z, TallyNextRow

;> drops -= 1
	dec hl
;> mem16[p] = drops
	ld a, h
	ld [de], a
	dec de
	ld a, l
	ld [de], a
;> AddScoreBCD(0x0001, addr(wScoreTally) + 22)      # the drop points shown in the tally
	ld de, $0001
	ld hl, wScoreTally + 22
	push de
	call AddScoreBCD
;> DrawBCDIfDirty(addr(wScoreTally) + 24, vBGMap0 + 0x1A5)
	ld de, wScoreTally + 24
	ld hl, vBGMap0 + $1A5
	call DrawBCDIfDirty
;> hTimer1 = 0
	xor a
	ldh [hTimer1], a
;> AddScoreBCD(0x0001, addr(wScore))
	pop de
	ld hl, wScore
	call AddScoreBCD
;> DrawBCD6(addr(wScore) + 2, vBGMap0 + 0x225)
	ld de, wScore + 2
	ld hl, vBGMap0 + $225
	call DrawBCD6
;> wSFXRequest = 2
	ld a, $02
	ld [wSFXRequest], a
;> return
	ret


;@ def UpdateTally()
;@ path: game/tally
;@ Called from VBlank: one counting step of the type B tally. The rows are
;@ singles, doubles, triples, tetrises (each worth its points times
;@ (level + 1)) and finally the soft drop points.
;@ reads: wTallyStep, wTallyRow, wScoreTally
;@ test: wTallyStep = rng.choice([0, 1, 1, 2])
;@ test: wTallyRow = rand(0, 4)
;@ test: hTypeBLevel = rand(0, 9)
;@ test: for k in range(4): mem[0xC0AC + 5 * k] = rng.choice([0, 3]); mem[0xC0AD + 5 * k] = rand_bcd(1); fill_bcd(0xC0AE + 5 * k, 3)
;@ test: mem[0xC0C0] = rng.choice([0, 7]); mem[0xC0C1] = 0
;@ test: fill_bcd(0xC0C2, 3)
;@ test: fill_bcd(0xC0A0, 3)
;@ sig: 71874cf2
UpdateTally::
;> if not wTallyStep: return
	ld a, [wTallyStep]
	and a
	ret z

;> if wTallyRow == 4: return TallyDropPoints()
	ld a, [wTallyRow]
	cp $04
	jr z, TallyDropPoints

;> points, where, counter = 0x0040, vBGMap0 + 0x023, 0       # singles
	ld de, $0040
	ld bc, vBGMap0 + $023
	ld hl, wScoreTally
;> if wTallyRow != 0:
	and a
	jr z, .count

;>     points, where, counter = 0x0100, vBGMap0 + 0x083, 5   # doubles
	ld de, $0100
	ld bc, vBGMap0 + $083
	ld hl, wScoreTally + 5
;>     if wTallyRow != 1:
	cp $01
	jr z, .count

;>         points, where, counter = 0x0300, vBGMap0 + 0x0E3, 10   # triples
	ld de, $0300
	ld bc, vBGMap0 + $0E3
	ld hl, wScoreTally + 10
;>         if wTallyRow != 2:
	cp $02
	jr z, .count

;>             points, where, counter = 0x1200, vBGMap0 + 0x143, 15   # tetrises
	ld de, $1200
	ld bc, vBGMap0 + $143
	ld hl, wScoreTally + 15

;> TallyCountStep(points, where, addr(wScoreTally) + counter)
.count
	call TallyCountStep
;> return
	ret


;@ def State0C_WaitButton()
;@ path: game/game_over
;@ Game state $0C: any button -> state $02.
;@ reads: hJoyPressed
;@ writes: hGameState
;@ test: hJoyPressed = rng.choice([0, 1])
;@ sig: 28fe853c
State0C_WaitButton::
;> if not hJoyPressed: return
	ldh a, [hJoyPressed]
	and a
	ret z

;> hGameState = 0x02
	ld a, $02
	ldh [hGameState], a
;> return
	ret


;@ def State0D_GameOverScreen()
;@ path: game/game_over
;@ Game state $0D: once the board has filled up, plays the game over music
;@ and shows GAME OVER / PLEASE TRY AGAIN. A type A score of 100000 or more
;@ launches a rocket instead (state $34) - the bigger the score, the bigger
;@ the rocket.
;@ reads: hTimer1, hTwoPlayer, hGameType, wScore
;@ writes: wMusicRequest, hTimer1, hSerialDone, hGameState, hRocketSprite
;@ test: hTimer1 = rng.choice([0, 0, 5])
;@ test: hTwoPlayer = rng.choice([0, 0, 1])
;@ test: hGameType = rng.choice([GAME_TYPE_A, GAME_TYPE_B])
;@ test: fill_bcd(0xC0A0, 3)
;@ test: mem[0xC0A2] = rng.choice([0x05, 0x10, 0x15, 0x20, 0x99])
;@ sig: d55ba1f8
State0D_GameOverScreen::
;> if hTimer1: return
	ldh a, [hTimer1]
	and a
	ret nz

;> wMusicRequest = 4                                # game over music
	ld a, $04
	ld [wMusicRequest], a
;> if hTwoPlayer:
	ldh a, [hTwoPlayer]
	and a
	jr z, .onePlayer

;>     hTimer1 = 63
	ld a, $3f
	ldh [hTimer1], a
;>     state = 0x1B
	ld a, $1b
;>     hSerialDone = 0x1B
	ldh [hSerialDone], a
;> else:
	jr .setState

;>     FillBoardAndRefresh(TILE_BLANK)
.onePlayer
	ld a, TILE_BLANK
	call FillBoardAndRefresh
;>     CopyTilemap8Wide(wBGMap0Copy + 0x043, GameOverText, 7)
	ld hl, wBGMap0Copy + $043
	ld de, GameOverText
	ld c, $07
	call CopyTilemap8Wide
;>     CopyTilemap8Wide(wBGMap0Copy + 0x183, TryAgainText, 6)
	ld hl, wBGMap0Copy + $183
	ld de, TryAgainText
	ld c, $06
	call CopyTilemap8Wide
;>     if hGameType == GAME_TYPE_A:
	ldh a, [hGameType]
	cp GAME_TYPE_A
	jr nz, .noRocket

;>         top = wScore[2]                          # score / 10000, BCD
	ld hl, wScore + 2
	ld a, [hl]
;>         rocket = 0x58                            # the bigger the score, the bigger the rocket
	ld b, $58
;>         if top < 0x20:
	cp $20
	jr nc, .rocket

;>             rocket += 1
	inc b
;>         if top < 0x15:
	cp $15
	jr nc, .rocket

;>             rocket += 1
	inc b
;>         if top >= 0x10:
	cp $10
	jr nc, .rocket

;>@rs             hRocketSprite = rocket
;>@rt             hTimer1 = 0x90
;>@rg             hGameState = 0x34                    # the rocket ending
;>@rr             return
;>     state = 0x04
.noRocket
	ld a, $04

;> hGameState = state
.setState
	ldh [hGameState], a
;> return
	ret

;=@rs
.rocket
	ld a, b
	ldh [hRocketSprite], a
;=@rt
	ld a, $90
	ldh [hTimer1], a
;=@rg
	ld a, $34
	ldh [hGameState], a
;=@rr
	ret


;@ def CopyTilemap8Wide(dest: hl, src: de, rows: c) -> de
;@ path: gfx/tilemaps
;@ Copies `rows` rows of 8 tiles from src to the BG map at dest. Returns the end of src.
;@ clobbers: a, bc, hl
;@ test: dest = rand(0x8000, 0xD800)
;@ test: src = rand(0x0000, 0x7000)
;@ test: rows = rand(1, 18)
;@ sig: 18dafa36
CopyTilemap8Wide::
;>@row for row in range(rows):
;>@line     line = dest
;>@col     for col in range(8):
	ld b, $08
;=@line
	push hl

;>         mem[dest] = mem[src]
.copy
	ld a, [de]
	ld [hli], a
;>         dest, src = dest + 1, src + 1
	inc de
;=@col
	dec b
	jr nz, .copy

;>     dest = line + 32
	pop hl
	push de
	ld de, $0020
	add hl, de
	pop de
;=@row
	dec c
	jr nz, CopyTilemap8Wide

;> return src
	ret


;@ def AwardLineClearPoints()
;@ path: game/score
;@ Type A: once the board refresh is under way (stage 5), pays the last line
;@ clear: 40 / 100 / 300 / 1200 points times (level + 1).
;@ reads: hGameType, hGameState, hBoardCopyStage, wScoreTally, hLevel
;@ writes: wScoreTally
;@ test: hGameType = rng.choice([GAME_TYPE_A, GAME_TYPE_A, GAME_TYPE_B])
;@ test: hGameState = rng.choice([0, 0, 0, 1])
;@ test: hBoardCopyStage = rng.choice([5, 5, 2])
;@ test: for k in range(4): mem[0xC0AC + 5 * k] = rng.choice([0, 0, 1])
;@ test: hLevel = rand(0, 20)
;@ test: fill_bcd(0xC0A0, 3)
;@ sig: 608b3b79
AwardLineClearPoints::
;> if hGameType != GAME_TYPE_A: return
	ldh a, [hGameType]
	cp GAME_TYPE_A
	ret nz

;> if hGameState != 0: return
	ldh a, [hGameState]
	and a
	ret nz

;> if hBoardCopyStage != 5: return
	ldh a, [hBoardCopyStage]
	cp $05
	ret nz

;> counter = addr(wScoreTally)                      # singles, doubles, triples, tetrises: 5 bytes apart
	ld hl, wScoreTally
	ld bc, $0005
;>@pt1 points = 0x0040                               # BCD
;>@if1 if not mem[counter]:
	ld a, [hl]
;=@pt1
	ld de, $0040
;=@if1
	and a
	jr nz, .pay

;>     counter += 5
	add hl, bc
;>@pt2     points = 0x0100
;>@if2     if not mem[counter]:
	ld a, [hl]
;=@pt2
	ld de, $0100
;=@if2
	and a
	jr nz, .pay

;>         counter += 5
	add hl, bc
;>@pt3         points = 0x0300
;>@if3         if not mem[counter]:
	ld a, [hl]
;=@pt3
	ld de, $0300
;=@if3
	and a
	jr nz, .pay

;>             counter += 5
	add hl, bc
;>             points = 0x1200
	ld de, $1200
;>             if not mem[counter]: return
	ld a, [hl]
	and a
	ret z

;> mem[counter] = 0
.pay
	ld [hl], $00
;>@add for _ in range(u8(hLevel + 1) or 256):
	ldh a, [hLevel]
	ld b, a
	inc b

;>     AddScoreBCD(points, addr(wScore))
.add
	push bc
	push de
	ld hl, wScore
	call AddScoreBCD
	pop de
	pop bc
;=@add
	dec b
	jr nz, .add

;> return
	ret


;@ def FillBoardAndRefresh(tile: a)
;@ path: game/setup
;@ Starts a board refresh, then fills the board with `tile` (see FillBoard).
;@ writes: hBoardCopyStage
;@ test: tile = rand(0, 255)
;@ sig: 568e5560
FillBoardAndRefresh::
;> hBoardCopyStage = 2
	push af
	ld a, $02
	ldh [hBoardCopyStage], a
	pop af
;> FillBoard(tile)                                 # falls through

;@ def FillBoard(tile: a)
;@ path: game/setup
;@ Fills the 10x18 board area of wBGMap0Copy with `tile`.
;@ clobbers: bc, de, hl
;@ test: tile = rand(0, 255)
;@ sig: 4abe5e3d
FillBoard::
;> p = wBGMap0Copy + 0x002
	ld hl, wBGMap0Copy + $002
;>@row for row in range(18):
	ld c, $12
	ld de, $0020

;>     fill(p, tile, 10)
.row
	push hl
	ld b, $0a

.loop
	ld [hli], a
	dec b
	jr nz, .loop

;>     p += 32
	pop hl
	add hl, de
;=@row
	dec c
	jr nz, .row

;> return
	ret


;@ def ClearHiddenRows()
;@ path: game/lines
;@ Clears the board columns of BG map rows 30 and 31 in wBGMap0Copy.
;@ clobbers: a, bc, de, hl
;@ sig: fb98aeb9
ClearHiddenRows::
;> p = wBGMap0Copy + 0x3C2
	ld hl, wBGMap0Copy + $3C2
	ld de, $0016
;>@tile tile = TILE_BLANK
;>@row for row in range(2):
	ld c, $02
;=@tile
	ld a, TILE_BLANK

;>     fill(p, tile, 10)
.row
	ld b, $0a

.loop
	ld [hli], a
	dec b
	jr nz, .loop

;>     p += 32
	add hl, de
;=@row
	dec c
	jr nz, .row

;> return
	ret


;@ def SpawnNextPiece()
;@ path: game/piece
;@ The next piece starts falling from the top, and a new next piece is
;@ chosen: from wPieceList in demos and 2-player games, otherwise with the
;@ randomizer. It rolls rDIV into one of the 7 pieces and rerolls (at most
;@ twice) when (last roll | roll | current piece) == current piece. It runs
;@ one piece ahead: the piece that becomes "next" is the previous roll.
;@ reads: hDemo, hTwoPlayer, hPieceListPos, hGarbagePending, rDIV, hNextPieceRoll, hFallDelayBase, wObjects
;@ writes: hPieceListPos, hGarbagePending, hNextPieceRoll, hFallDelay, wObjects
;@ test: hDemo = rng.choice([0, 0, 1])
;@ test: hTwoPlayer = 0
;@ test: hGarbagePending = rng.choice([0, 1])
;@ test: hNextPieceRoll = 4 * rand(0, 6)
;@ test: mem[0xC213] = 4 * rand(0, 6) + rand(0, 3)
;@ test: for i in range(256): mem[0xC300 + i] = 4 * rand(0, 6)
;@ test: mem[0xC210] = rng.choice([0, 0x80])
;@ test: hObjHidden = 0
;@ sig: 6f5da524
SpawnNextPiece::
;> wObjects[0] = 0                                  # the next piece starts at the top
	ld hl, wObjects
	ld [hl], $00
;> wObjects[1] = 0x18
	inc l
	ld [hl], $18
;> wObjects[2] = 0x3F
	inc l
	ld [hl], $3f
;> wObjects[3] = wObjects[0x13]
	inc l
	ld a, [wObjects + $13]
	ld [hl], a
;> current = wObjects[0x13] & 0xFC                  # piece type (sprite id without rotation)
	and $fc
	ld c, a
;> if hDemo or hTwoPlayer:                          # fixed sequence
	ldh a, [hDemo]
	and a
	jr nz, .fromList

	ldh a, [hTwoPlayer]
	and a
	jr z, .random

;>     next = wPieceList[hPieceListPos]
.fromList
	ld h, HIGH(wPieceList)
	ldh a, [hPieceListPos]
	ld l, a
	ld e, [hl]
;>     pos = hPieceListPos + 1
	inc hl
;>     if pos == 0x100: pos = 0
	ld a, h
	cp HIGH(wPieceList) + 1
	jr nz, .storePos

	ld hl, wPieceList

;>     hPieceListPos = pos
.storePos
	ld a, l
	ldh [hPieceListPos], a
;>     if hGarbagePending:
	ldh a, [hGarbagePending]
	and a
	jr z, .setNext

;>         hGarbagePending |= 0x80
	or $80
	ldh [hGarbagePending], a
;> else:
	jr .setNext

;>@try     for attempt in range(3):
.random
	ld h, $03

;>         n = rDIV
.roll
	ldh a, [rDIV]
	ld b, a

;>         roll = 0                                 # piece type * 4: counts n - 1 steps mod 7
.wrap
	xor a

;>@count         for _ in range(u8(n - 1)):
.count
	dec b
	jr z, .rolled

;>             roll += 4
	inc a
	inc a
	inc a
	inc a
;>             if roll == 0x1C: roll = 0
	cp $1c
	jr z, .wrap

;=@count
	jr .count

;>         next = hNextPieceRoll                    # the previous roll
.rolled
	ld d, a
	ldh a, [hNextPieceRoll]
	ld e, a
;>         if attempt == 2: break
	dec h
	jr z, .accept

;>         if (hNextPieceRoll | roll | current) & 0xFC != current: break
	or d
	or c
	and $fc
	cp c
;=@try
	jr z, .roll

;>     hNextPieceRoll = roll
.accept
	ld a, d
	ldh [hNextPieceRoll], a

;> wObjects[0x13] = next
.setNext
	ld a, e
	ld [wObjects + $13], a
;> DrawObject1()
	call DrawObject1
;> hFallDelay = hFallDelayBase
	ldh a, [hFallDelayBase]
	ldh [hFallDelay], a
;> return
	ret

; part of UpdateFall (it jumps here when only Down is held): the soft drop branch
;=@UpdateFall.chk
UpdateFallSoftDrop:
	ld a, [wBoardCopyDone]
	and a
	jr z, .check

;=@UpdateFall.chk2
	ldh a, [hJoyPressed]
	and $b0
	cp $80
	jr nz, UpdateFall.gravity

;=@UpdateFall.clr
	xor a
	ld [wBoardCopyDone], a

;=@UpdateFall.busy1
.check
	ldh a, [hTimer2]
	and a
	jr nz, UpdateFall.draw

;=@UpdateFall.busy2
	ldh a, [hPiecePhase]
	and a
	jr nz, UpdateFall.draw

;=@UpdateFall.busy3
	ldh a, [hBoardCopyStage]
	and a
	jr nz, UpdateFall.draw

;=@UpdateFall.t2
	ld a, $03
	ldh [hTimer2], a
;=@UpdateFall.rows
	ld hl, hSoftDropRows
	inc [hl]
	jr UpdateFall.moveDown

;@ def UpdateFall()
;@ path: game/piece
;@ Gravity and soft drop for the falling piece. When it can't move down any
;@ more it has landed: soft drop points are paid, and a piece that lands at
;@ the spawn position for the second time ends the game.
;@ reads: hJoyHeld, hJoyPressed, wBoardCopyDone, hTimer2, hPiecePhase, hBoardCopyStage, hFallDelay, hFallDelayBase, hSoftDropRows, hGameType, hSpawnBlocked, wObjects
;@ writes: wBoardCopyDone, hTimer2, hSoftDropRows, hFallDelay, hTemp, hPiecePhase, wScoreTally, wScoreDirty, hSpawnBlocked, hGameState, wWaveSFXRequest
;@ test: hJoyHeld = rng.choice([0, BTN_DOWN, BTN_DOWN, BTN_DOWN | BTN_LEFT])
;@ test: hJoyPressed = rng.choice([0, BTN_DOWN])
;@ test: wBoardCopyDone = rng.choice([0, 0, 1])
;@ test: hTimer2 = rng.choice([0, 0, 2])
;@ test: hPiecePhase = rng.choice([0, 0, 0, 3])
;@ test: hBoardCopyStage = rng.choice([0, 0, 0, 2])
;@ test: hFallDelay = rng.choice([0, 0, 5])
;@ test: hSoftDropRows = rng.choice([0, 3, 40])
;@ test: hGameType = rng.choice([GAME_TYPE_A, GAME_TYPE_B])
;@ test: hSpawnBlocked = rng.choice([0, 2])
;@ test: fill_bcd(0xC0A0, 3)
;@ test: mem[0xC200] = 0
;@ test: mem[0xC201] = rng.choice([0x18, 0x40])
;@ test: mem[0xC202] = rng.choice([0x3F, 0x47])
;@ test: mem[0xC203] = rand(0, 27)
;@ test: hObjHidden = 0
;@ sig: 6bd3c6e2
UpdateFall::
;> soft = (hJoyHeld & (BTN_DOWN | BTN_LEFT | BTN_RIGHT)) == BTN_DOWN   # (soft drop: in UpdateFallSoftDrop)
	ldh a, [hJoyHeld]
	and $b0
	cp $80
	jr z, UpdateFallSoftDrop

;>@chk if soft and wBoardCopyDone:                      # after a landing, Down must be pressed again
;>@chk2     if (hJoyPressed & 0xB0) == BTN_DOWN:
;>@clr         wBoardCopyDone = 0
;>@nosoft     else:
;>         soft = False
;>@sd if soft:
;>@busy1     if (hTimer2 or
;>@busy2             hPiecePhase or
;>@busy3             hBoardCopyStage):
;>@bd         DrawObject0()
;>@br         return
;>@t2     hTimer2 = 3                                  # one row every 3 frames
;>@rows     hSoftDropRows += 1
;> else:
;>     hSoftDropRows = 0
.gravity:
	ld hl, hSoftDropRows
	ld [hl], $00
;>     if hFallDelay:
	ldh a, [hFallDelay]
	and a
	jr z, .fall

;>         hFallDelay -= 1
	dec a
	ldh [hFallDelay], a

;>         DrawObject0()
.draw:
	call DrawObject0
;>         return
	ret

;>     if hPiecePhase == 3: return
.fall:
	ldh a, [hPiecePhase]
	cp $03
	ret z

;>     if hBoardCopyStage: return
	ldh a, [hBoardCopyStage]
	and a
	ret nz

;>     hFallDelay = hFallDelayBase
	ldh a, [hFallDelayBase]
	ldh [hFallDelay], a

;> hTemp = wObjects[1]                              # one row down
.moveDown:
	ld hl, wObjects + $01
	ld a, [hl]
	ldh [hTemp], a
;> wObjects[1] = hTemp + 8
	add $08
	ld [hl], a
;> DrawObject0()
	call DrawObject0
;> if not PieceCollides(): return
	call PieceCollides
	and a
	ret z

;> wObjects[1] = hTemp                              # blocked: undo, the piece has landed
	ldh a, [hTemp]
	ld hl, wObjects + $01
	ld [hl], a
;> DrawObject0()
	call DrawObject0
;> hPiecePhase = 1
	ld a, $01
	ldh [hPiecePhase], a
;> wBoardCopyDone = 1
	ld [wBoardCopyDone], a
;> if hSoftDropRows:                                # soft drop points: rows - 1
	ldh a, [hSoftDropRows]
	and a
	jr z, .checkSpawn

;>     if hGameType == GAME_TYPE_A:
	ld c, a
	ldh a, [hGameType]
	cp GAME_TYPE_A
	jr z, .softDropPointsA

;>@pts0         points = 0
;>@bcd         for _ in range(hSoftDropRows - 1):
;>@inc             points = to_bcd(bcd_to_int(points) + 1)
;>@add         AddScoreBCD(points, addr(wScore))
;>@dirty         wScoreDirty = 1
;>     else:                                        # type B: paid at the end
;>         p = addr(wScoreTally) + 20
	ld de, wScoreTally + 20
;>         drops = mem16[p]
	ld a, [de]
	ld l, a
	inc de
	ld a, [de]
	ld h, a
;>         drops = u16(drops + hSoftDropRows - 1)
	ld b, $00
	dec c
	add hl, bc
;>         mem16[p] = drops
	ld a, h
	ld [de], a
	ld a, l
	dec de
	ld [de], a

;>     hSoftDropRows = 0
.softDropDone:
	xor a
	ldh [hSoftDropRows], a

;> if wObjects[1] != 0x18: return
.checkSpawn:
	ld a, [wObjects + $01]
	cp $18
	ret nz

;> if wObjects[2] != 0x3F: return                   # it never left the spawn position
	ld a, [wObjects + $02]
	cp $3f
	ret nz

;> if hSpawnBlocked == 1:                           # the second time: game over
	ld hl, hSpawnBlocked
	ld a, [hl]
	cp $01
	jr nz, .firstBlock

;>     InitSound()
	call InitSound
;>     hGameState = 0x01
	ld a, $01
	ldh [hGameState], a
;>     wWaveSFXRequest = 2
	ld a, $02
	ld [wWaveSFXRequest], a
;>     return
	ret

;> hSpawnBlocked += 1
.firstBlock:
	inc [hl]
;> return
	ret

;=@pts0
.softDropPointsA:
	xor a

;=@bcd
.toBCD:
	dec c
	jr z, .addScore

;=@inc
	inc a
	daa
;=@bcd
	jr .toBCD

;=@add
.addScore:
	ld e, a
	ld d, $00
	ld hl, wScore
	call AddScoreBCD
;=@dirty
	ld a, $01
	ld [wScoreDirty], a
	jr .softDropDone

;@ def CheckLines()
;@ path: game/lines
;@ Phase 2 (piece locked): finds the full rows (board rows 2-17), updates the
;@ line counter (type A counts up to 9999, type B counts down) and the
;@ line clear counters, and starts the line clear animation.
;@ reads: hPiecePhase, hGameType, hLines
;@ writes: wNoiseSFXRequest, hTemp, wClearedRows, hPiecePhase, hTimer1, hLines, wScoreTally, hLineClearKind, wSFXRequest
;@ test: hPiecePhase = rng.choice([2, 2, 0])
;@ test: hGameType = rng.choice([GAME_TYPE_A, GAME_TYPE_B])
;@ test: hLines = rand_bcd(2)
;@ test: for r in range(16): mem[0xC842 + 32 * r + rand(0, 9)] = rng.choice([0x2F, 0x2F, 0x80])
;@ sig: 7a3a9a99
CheckLines::
;> if hPiecePhase != 2: return
	ldh a, [hPiecePhase]
	cp $02
	ret nz

;> wNoiseSFXRequest = 2                             # the "piece locked" sound
	ld a, $02
	ld [wNoiseSFXRequest], a
;> hTemp = 0                                        # number of full rows
	xor a
	ldh [hTemp], a
;> found = addr(wClearedRows)
	ld de, wClearedRows
;> line = wBGMap0Copy + 0x42
	ld hl, wBGMap0Copy + $042
;>@row for row in range(16):
	ld b, $10

;>@cell     for i in range(10):
.row:
	ld c, $0a
	push hl

;>         if mem[line + i] == TILE_BLANK:
.cell:
	ld a, [hli]
	cp TILE_BLANK
	jp z, .notFull

;>@brk             break
;=@cell
	dec c
	jr nz, .cell

;>     else:                                        # no blank: the row is full
	pop hl
;>         mem[found] = hi(line)
	ld a, h
	ld [de], a
;>         found += 1
	inc de
;>         mem[found] = lo(line)
	ld a, l
	ld [de], a
;>         found += 1
	inc de
;>         hTemp += 1
	ldh a, [hTemp]
	inc a
	ldh [hTemp], a

;>     line += 32
.nextRow:
	push de
	ld de, $0020
	add hl, de
	pop de
;=@row
	dec b
	jr nz, .row

;> hPiecePhase = 3                                  # AnimateLineClear
	ld a, $03
	ldh [hPiecePhase], a
;> hTimer1 = 2
	dec a
	ldh [hTimer1], a
;> if hTemp == 0: return
	ldh a, [hTemp]
	and a
	ret z

;> count = hTemp
	ld b, a
	ld hl, hLines
;> if hGameType == GAME_TYPE_A:
	ldh a, [hGameType]
	cp GAME_TYPE_B
	jr z, .typeB

;>     low = bcd_to_int(mem[addr(hLines)]) + count
	ld a, b
	add [hl]
	daa
;>     mem[addr(hLines)] = to_bcd(low)
	ld [hli], a
;>     high = bcd_to_int(mem[addr(hLines) + 1]) + low // 100
	ld a, $00
	adc [hl]
	daa
;>     mem[addr(hLines) + 1] = to_bcd(high)
	ld [hl], a
;>     if high >= 100:                              # at most 9999
	jr nc, .countKind

;>         bcd_write(addr(hLines), 2, 9999)
	ld [hl], $99
	dec hl
	ld [hl], $99
;> else:                                            # type B: lines still to clear
	jr .countKind

;>     left = bcd_to_int(lo(hLines)) - count
.typeB:
	ld a, [hl]
	or a
	sub b
;>     if left > 0:
	jr z, .noneLeft

	jr c, .noneLeft

;>         hLines = (hLines & 0xFF00) | to_bcd(left)
	daa
	ld [hl], a
;>     if not 0 < left < 90:
	and $f0
	cp $90
	jr z, .noneLeft

;>@none         hLines = hLines & 0xFF00
;> sound = 6
.countKind:
	ld a, b
	ld c, $06
;> counter, kind = 0, 0                             # singles
	ld hl, wScoreTally
	ld b, $00
;> if count != 1:
	cp $01
	jr z, .store

;>     counter, kind = 5, 1                         # doubles
	ld hl, wScoreTally + 5
	ld b, $01
;>     if count != 2:
	cp $02
	jr z, .store

;>         counter, kind = 10, 2                    # triples
	ld hl, wScoreTally + 10
	ld b, $02
;>         if count != 3:
	cp $03
	jr z, .store

;>             counter, kind, sound = 15, 4, 7      # tetrises
	ld hl, wScoreTally + 15
	ld b, $04
	ld c, $07

;> wScoreTally[counter] += 1                        # singles / doubles / triples / tetrises
.store:
	inc [hl]
;> hLineClearKind = kind
	ld a, b
	ldh [hLineClearKind], a
;> wSFXRequest = sound
	ld a, c
	ld [wSFXRequest], a
;> return
	ret

;=@brk
.notFull:
	pop hl
	jr .nextRow

;=@none
.noneLeft:
	xor a
	ldh [hLines], a
	jr .countKind



;@ def AnimateLineClear()
;@ path: game/lines
;@ Phase 3, run from VBlank every 10 frames: the full rows flash - even steps
;@ fill them with tile $8C (step 6: blank), odd steps show their content
;@ again. After 7 steps CollapseClearedRows takes over. Without full rows
;@ the next piece spawns right away.
;@ reads: hPiecePhase, hTimer1, hClearAnimPhase, wClearedRows
;@ writes: hClearAnimPhase, hTimer1, hBoardCopyStage, hPiecePhase
;@ test: hPiecePhase = rng.choice([3, 3, 0])
;@ test: hTimer1 = rng.choice([0, 0, 4])
;@ test: hClearAnimPhase = rand(0, 6)
;@ test: for i in range(4): mem[0xC0A3 + 2 * i] = 0xC8 + rand(0, 3); mem[0xC0A4 + 2 * i] = rand(0, 0xF6)
;@ test: mem[0xC0A3 + 2 * rand(1, 4)] = 0
;@ test: mem[0xC0AB] = 0
;@ test: hDemo = 1
;@ test: for i in range(256): mem[0xC300 + i] = 4 * rand(0, 6)
;@ test: mem[0xC210] = rng.choice([0, 0x80])
;@ test: hObjHidden = 0
;@ sig: b0b7883a
AnimateLineClear::
;> if hPiecePhase != 3: return
	ldh a, [hPiecePhase]
	cp $03
	ret nz

;> if hTimer1: return
	ldh a, [hTimer1]
	and a
	ret nz

;> rows = addr(wClearedRows)                        # pairs (high, low) of row addresses in wBGMap0Copy
	ld de, wClearedRows
;> if hClearAnimPhase & 1:                          # odd step: show the rows again
	ldh a, [hClearAnimPhase]
	bit 0, a
	jr nz, .showRow

;>@show     while True:
;>@srchi         src = mem[rows] << 8
;>@dsthi         dst_hi = mem[rows] - 0x30                # the same row on BG map 0
;>@rows1         rows += 1
;>@srclo         src |= mem[rows]
;>@cells         for i in range(10):
;>@copy             mem[dst_hi << 8 | lo(src)] = mem[src]
;>@src1             src += 1
;>@rows2         rows += 1
;>@end         if not mem[rows]: break
;>@else else:
;>     if not mem[rows]:                            # no full rows: next piece now
	ld a, [de]
	and a
	jr z, .noRows

;>@spawn         SpawnNextPiece()
;>@ph0         hPiecePhase = 0
;>@ret0         return
;>@blank     while True:
;>         dst = (mem[rows] - 0x30) << 8            # the row on BG map 0
.blankRow:
	sub HIGH(wBGMap0Copy - vBGMap0)
	ld h, a
;>         rows += 1
	inc de
;>         dst |= mem[rows]
	ld a, [de]
	ld l, a
;>         tile = TILE_BLANK if hClearAnimPhase == 6 else 0x8C
	ldh a, [hClearAnimPhase]
	cp $06
	ld a, $8c
	jr nz, .fillRow

	ld a, TILE_BLANK

;>@fill         for i in range(10):
.fillRow:
	ld c, $0a

;>             mem[dst + i] = tile
.fillCell:
	ld [hli], a
;=@fill
	dec c
	jr nz, .fillCell

;>         rows += 1
	inc de
;>         if not mem[rows]: break
	ld a, [de]
	and a
;=@blank
	jr nz, .blankRow

;> hClearAnimPhase += 1
.nextStep:
	ldh a, [hClearAnimPhase]
	inc a
	ldh [hClearAnimPhase], a
;> if hClearAnimPhase != 7:
	cp $07
	jr z, .done

;>     hTimer1 = 10
	ld a, $0a
	ldh [hTimer1], a
;>     return
	ret

;> hClearAnimPhase = 0
.done:
	xor a
	ldh [hClearAnimPhase], a
;> hTimer1 = 13
	ld a, $0d
	ldh [hTimer1], a
;> hBoardCopyStage = 1                              # CollapseClearedRows
	ld a, $01
	ldh [hBoardCopyStage], a

;> hPiecePhase = 0
.phase0:
	xor a
	ldh [hPiecePhase], a
;> return
	ret

;=@srchi
.showRow:
	ld a, [de]
	ld h, a
;=@dsthi
	sub HIGH(wBGMap0Copy - vBGMap0)
	ld c, a
;=@rows1
	inc de
;=@srclo
	ld a, [de]
	ld l, a
;=@cells
	ld b, $0a

;=@copy
.showCell:
	ld a, [hl]
	push hl
	ld h, c
	ld [hl], a
	pop hl
;=@src1
	inc hl
;=@cells
	dec b
	jr nz, .showCell

;=@rows2
	inc de
;=@end
	ld a, [de]
	and a
;=@show
	jr nz, .showRow

;=@else
	jr .nextStep

;=@spawn
.noRows:
	call SpawnNextPiece
;=@ph0
	jr .phase0

;@ def CollapseClearedRows()
;@ path: game/lines
;@ After the line clear animation: for every cleared row, everything above
;@ it moves down one row in wBGMap0Copy; then the top row is cleared and a
;@ full board refresh starts.
;@ reads: hTimer1, hBoardCopyStage, wClearedRows
;@ writes: hBoardCopyStage
;@ test: hTimer1 = rng.choice([0, 0, 4])
;@ test: hBoardCopyStage = rng.choice([1, 1, 0])
;@ test: for i in range(4): v = 0xC802 + 32 * rand(2, 17); mem[0xC0A3 + 2 * i] = v >> 8; mem[0xC0A4 + 2 * i] = v & 0xFF
;@ test: mem[0xC0A3 + 2 * rand(1, 4)] = 0
;@ sig: b2f510f0
CollapseClearedRows::
;> if hTimer1: return
	ldh a, [hTimer1]
	and a
	ret nz

;> if hBoardCopyStage != 1: return
	ldh a, [hBoardCopyStage]
	cp $01
	ret nz

;> rows = addr(wClearedRows)
	ld de, wClearedRows
	ld a, [de]

;>@rows while True:
;>     dest = mem[rows] << 8 | mem[rows + 1]
.nextRow
	ld h, a
	inc de
	ld a, [de]
	ld l, a
;>     src = dest - 32
	push de
	push hl
	ld bc, -32
	add hl, bc
	pop de

;>@move     while True:                                  # move every row above down by one
;>         copy(dest, src, 10)
.moveDown
	push hl
	ld b, $0a

.copy
	ld a, [hli]
	ld [de], a
	inc de
	dec b
	jr nz, .copy

;>         dest, src = src, src - 32
	pop hl
	push hl
	pop de
	ld bc, -32
	add hl, bc
;>         if hi(src) == 0xC7: break                # above the top of wBGMap0Copy
	ld a, h
	cp HIGH(wBGMap0Copy) - 1
;=@move
	jr nz, .moveDown

;>     rows += 2
	pop de
	inc de
;>     if not mem[rows]: break
	ld a, [de]
	and a
;=@rows
	jr nz, .nextRow

;> fill(wBGMap0Copy + 2, TILE_BLANK, 10)           # new empty top row
	ld hl, wBGMap0Copy + $002
	ld a, TILE_BLANK
	ld b, $0a

.clearTop
	ld [hli], a
	dec b
	jr nz, .clearTop

;> ClearClearedRows()                                   # forget the cleared rows
	call ClearClearedRows
;> hBoardCopyStage = 2                              # copy the whole board to VRAM
	ld a, $02
	ldh [hBoardCopyStage], a
;> return
	ret


;@ def ClearClearedRows()
;@ path: game/lines
;@ Clears the 9 bytes of wClearedRows.
;@ clobbers: a, b, hl
;@ sig: 0facdca0
ClearClearedRows::
;> fill(wClearedRows, 0, 9)
	ld hl, wClearedRows
	xor a
	ld b, $09

.loop
	ld [hli], a
	dec b
	jr nz, .loop

;> return
	ret


;@ def RefreshBoardRow17()
;@ path: game/board_refresh
;@ Board refresh, stage $02: copies board row 17 from wBGMap0Copy to VRAM.
;@ reads: hBoardCopyStage
;@ writes: hBoardCopyStage
;@ test: hBoardCopyStage = rng.choice([$02, $02, 0])
;@ sig: 9c882b8e
RefreshBoardRow17::
;> if hBoardCopyStage != 0x02: return
	ldh a, [hBoardCopyStage]
	cp $02
	ret nz
;> CopyBoardRow(vBGMap0 + 0x222, wBGMap0Copy + 0x222)
	ld hl, vBGMap0 + $222
	ld de, wBGMap0Copy + $222
	call CopyBoardRow
	ret


;@ def RefreshBoardRow16()
;@ path: game/board_refresh
;@ Board refresh, stage $03: copies board row 16 from wBGMap0Copy to VRAM.
;@ reads: hBoardCopyStage
;@ writes: hBoardCopyStage
;@ test: hBoardCopyStage = rng.choice([$03, $03, 0])
;@ sig: 8270e074
RefreshBoardRow16::
;> if hBoardCopyStage != 0x03: return
	ldh a, [hBoardCopyStage]
	cp $03
	ret nz
;> CopyBoardRow(vBGMap0 + 0x202, wBGMap0Copy + 0x202)
	ld hl, vBGMap0 + $202
	ld de, wBGMap0Copy + $202
	call CopyBoardRow
	ret


;@ def RefreshBoardRow15()
;@ path: game/board_refresh
;@ Board refresh, stage $04: copies board row 15 from wBGMap0Copy to VRAM.
;@ reads: hBoardCopyStage
;@ writes: hBoardCopyStage
;@ test: hBoardCopyStage = rng.choice([$04, $04, 0])
;@ sig: 13b5eea1
RefreshBoardRow15::
;> if hBoardCopyStage != 0x04: return
	ldh a, [hBoardCopyStage]
	cp $04
	ret nz
;> CopyBoardRow(vBGMap0 + 0x1E2, wBGMap0Copy + 0x1E2)
	ld hl, vBGMap0 + $1E2
	ld de, wBGMap0Copy + $1E2
	call CopyBoardRow
	ret


;@ def RefreshBoardRow14()
;@ path: game/board_refresh
;@ Board refresh, stage $05: copies board row 14 from wBGMap0Copy to VRAM.
;@ reads: hBoardCopyStage
;@ writes: hBoardCopyStage
;@ test: hBoardCopyStage = rng.choice([$05, $05, 0])
;@ sig: 0d4d255b
RefreshBoardRow14::
;> if hBoardCopyStage != 0x05: return
	ldh a, [hBoardCopyStage]
	cp $05
	ret nz
;> CopyBoardRow(vBGMap0 + 0x1C2, wBGMap0Copy + 0x1C2)
	ld hl, vBGMap0 + $1C2
	ld de, wBGMap0Copy + $1C2
	call CopyBoardRow
	ret


;@ def RefreshBoardRow13()
;@ path: game/board_refresh
;@ Board refresh, stage $06: copies board row 13 from wBGMap0Copy to VRAM.
;@ reads: hBoardCopyStage
;@ writes: hBoardCopyStage
;@ test: hBoardCopyStage = rng.choice([$06, $06, 0])
;@ sig: 2e447955
RefreshBoardRow13::
;> if hBoardCopyStage != 0x06: return
	ldh a, [hBoardCopyStage]
	cp $06
	ret nz
;> CopyBoardRow(vBGMap0 + 0x1A2, wBGMap0Copy + 0x1A2)
	ld hl, vBGMap0 + $1A2
	ld de, wBGMap0Copy + $1A2
	call CopyBoardRow
	ret


;@ def RefreshBoardRow12()
;@ path: game/board_refresh
;@ Board refresh, stage $07: copies board row 12 from wBGMap0Copy to VRAM.
;@ reads: hBoardCopyStage
;@ writes: hBoardCopyStage
;@ test: hBoardCopyStage = rng.choice([$07, $07, 0])
;@ sig: 30bcb2af
RefreshBoardRow12::
;> if hBoardCopyStage != 0x07: return
	ldh a, [hBoardCopyStage]
	cp $07
	ret nz
;> CopyBoardRow(vBGMap0 + 0x182, wBGMap0Copy + 0x182)
	ld hl, vBGMap0 + $182
	ld de, wBGMap0Copy + $182
	call CopyBoardRow
	ret


;@ def RefreshBoardRow11()
;@ path: game/board_refresh
;@ Board refresh, stage $08: copies board row 11 from wBGMap0Copy to VRAM.
;@ reads: hBoardCopyStage
;@ writes: hBoardCopyStage
;@ After the copy it requests a sound in some game states.
;@ reads: hTwoPlayer, hGameState, hGarbageAdded
;@ writes: wNoiseSFXRequest, wSFXRequest
;@ test: hTwoPlayer = rng.choice([0, 1])
;@ test: hGameState = rng.choice([0, 0x1A, 3])
;@ test: hBoardCopyStage = rng.choice([$08, $08, 0])
;@ sig: 0fa7ce8b
RefreshBoardRow11::
;> if hBoardCopyStage != 0x08: return
	ldh a, [hBoardCopyStage]
	cp $08
	ret nz
;> CopyBoardRow(vBGMap0 + 0x162, wBGMap0Copy + 0x162)
	ld hl, vBGMap0 + $162
	ld de, wBGMap0Copy + $162
	call CopyBoardRow
;> if not hTwoPlayer:
	ldh a, [hTwoPlayer]
	and a
	ldh a, [hGameState]
	jr nz, .twoPlayer
;>     if hGameState != 0: return
	and a
	ret nz

;>     wNoiseSFXRequest = 1
.noiseSFX
	ld a, $01
	ld [wNoiseSFXRequest], a
;>     return
	ret

;> if hGameState != 0x1A: return
.twoPlayer
	cp $1a
	ret nz

;> if not hGarbageAdded:                       # (jumps to the request above)
	ldh a, [hGarbageAdded]
	and a
	jr z, .noiseSFX

;>@gnoise     wNoiseSFXRequest = 1
;>@gret     return
;> wSFXRequest = 5
	ld a, $05
	ld [wSFXRequest], a
;> return
	ret


;@ def RefreshBoardRow10()
;@ path: game/board_refresh
;@ Board refresh, stage $09: copies board row 10 from wBGMap0Copy to VRAM.
;@ reads: hBoardCopyStage
;@ writes: hBoardCopyStage
;@ test: hBoardCopyStage = rng.choice([$09, $09, 0])
;@ sig: 70a27c4d
RefreshBoardRow10::
;> if hBoardCopyStage != 0x09: return
	ldh a, [hBoardCopyStage]
	cp $09
	ret nz
;> CopyBoardRow(vBGMap0 + 0x142, wBGMap0Copy + 0x142)
	ld hl, vBGMap0 + $142
	ld de, wBGMap0Copy + $142
	call CopyBoardRow
	ret


;@ def RefreshBoardRow9()
;@ path: game/board_refresh
;@ Board refresh, stage $0A: copies board row 9 from wBGMap0Copy to VRAM.
;@ reads: hBoardCopyStage
;@ writes: hBoardCopyStage
;@ test: hBoardCopyStage = rng.choice([$0A, $0A, 0])
;@ sig: 53ab2043
RefreshBoardRow9::
;> if hBoardCopyStage != 0x0A: return
	ldh a, [hBoardCopyStage]
	cp $0a
	ret nz
;> CopyBoardRow(vBGMap0 + 0x122, wBGMap0Copy + 0x122)
	ld hl, vBGMap0 + $122
	ld de, wBGMap0Copy + $122
	call CopyBoardRow
	ret


;@ def RefreshBoardRow8()
;@ path: game/board_refresh
;@ Board refresh, stage $0B: copies board row 8 from wBGMap0Copy to VRAM.
;@ reads: hBoardCopyStage
;@ writes: hBoardCopyStage
;@ test: hBoardCopyStage = rng.choice([$0B, $0B, 0])
;@ sig: 4d53ebb9
RefreshBoardRow8::
;> if hBoardCopyStage != 0x0B: return
	ldh a, [hBoardCopyStage]
	cp $0b
	ret nz
;> CopyBoardRow(vBGMap0 + 0x102, wBGMap0Copy + 0x102)
	ld hl, vBGMap0 + $102
	ld de, wBGMap0Copy + $102
	call CopyBoardRow
	ret


;@ def RefreshBoardRow7()
;@ path: game/board_refresh
;@ Board refresh, stage $0C: copies board row 7 from wBGMap0Copy to VRAM.
;@ reads: hBoardCopyStage
;@ writes: hBoardCopyStage
;@ test: hBoardCopyStage = rng.choice([$0C, $0C, 0])
;@ sig: e473b171
RefreshBoardRow7::
;> if hBoardCopyStage != 0x0C: return
	ldh a, [hBoardCopyStage]
	cp $0c
	ret nz
;> CopyBoardRow(vBGMap0 + 0x0E2, wBGMap0Copy + 0x0E2)
	ld hl, vBGMap0 + $0E2
	ld de, wBGMap0Copy + $0E2
	call CopyBoardRow
	ret


;@ def RefreshBoardRow6()
;@ path: game/board_refresh
;@ Board refresh, stage $0D: copies board row 6 from wBGMap0Copy to VRAM.
;@ reads: hBoardCopyStage
;@ writes: hBoardCopyStage
;@ test: hBoardCopyStage = rng.choice([$0D, $0D, 0])
;@ sig: fa8b7a8b
RefreshBoardRow6::
;> if hBoardCopyStage != 0x0D: return
	ldh a, [hBoardCopyStage]
	cp $0d
	ret nz
;> CopyBoardRow(vBGMap0 + 0x0C2, wBGMap0Copy + 0x0C2)
	ld hl, vBGMap0 + $0C2
	ld de, wBGMap0Copy + $0C2
	call CopyBoardRow
	ret


;@ def RefreshBoardRow5()
;@ path: game/board_refresh
;@ Board refresh, stage $0E: copies board row 5 from wBGMap0Copy to VRAM.
;@ reads: hBoardCopyStage
;@ writes: hBoardCopyStage
;@ test: hBoardCopyStage = rng.choice([$0E, $0E, 0])
;@ sig: d9822685
RefreshBoardRow5::
;> if hBoardCopyStage != 0x0E: return
	ldh a, [hBoardCopyStage]
	cp $0e
	ret nz
;> CopyBoardRow(vBGMap0 + 0x0A2, wBGMap0Copy + 0x0A2)
	ld hl, vBGMap0 + $0A2
	ld de, wBGMap0Copy + $0A2
	call CopyBoardRow
	ret


;@ def RefreshBoardRow4()
;@ path: game/board_refresh
;@ Board refresh, stage $0F: copies board row 4 from wBGMap0Copy to VRAM.
;@ reads: hBoardCopyStage
;@ writes: hBoardCopyStage
;@ test: hBoardCopyStage = rng.choice([$0F, $0F, 0])
;@ sig: c77aed7f
RefreshBoardRow4::
;> if hBoardCopyStage != 0x0F: return
	ldh a, [hBoardCopyStage]
	cp $0f
	ret nz
;> CopyBoardRow(vBGMap0 + 0x082, wBGMap0Copy + 0x082)
	ld hl, vBGMap0 + $082
	ld de, wBGMap0Copy + $082
	call CopyBoardRow
	ret


;@ def RefreshBoardRow3()
;@ path: game/board_refresh
;@ Board refresh, stage $10: copies board row 3 from wBGMap0Copy to VRAM.
;@ reads: hBoardCopyStage
;@ writes: hBoardCopyStage
;@ Then checks whether the level goes up.
;@ test: hBoardCopyStage = rng.choice([$10, $10, 0])
;@ sig: 7958532e
RefreshBoardRow3::
;> if hBoardCopyStage != 0x10: return
	ldh a, [hBoardCopyStage]
	cp $10
	ret nz
;> CopyBoardRow(vBGMap0 + 0x062, wBGMap0Copy + 0x062)
	ld hl, vBGMap0 + $062
	ld de, wBGMap0Copy + $062
	call CopyBoardRow
;> CheckLevelUp()
	call CheckLevelUp
	ret


;@ def RefreshBoardRow2()
;@ path: game/board_refresh
;@ Board refresh, stage $11: copies board row 2 from wBGMap0Copy to VRAM.
;@ reads: hBoardCopyStage
;@ writes: hBoardCopyStage
;@ Then redraws the score on BG map 1 and forces the next stage to redraw it on map 0.
;@ writes: hDrawBCDFlag
;@ test: hGameState = rng.choice([0, 1])
;@ test: hBoardCopyStage = rng.choice([$11, $11, 0])
;@ sig: 2d794589
RefreshBoardRow2::
;> if hBoardCopyStage != 0x11: return
	ldh a, [hBoardCopyStage]
	cp $11
	ret nz
;> CopyBoardRow(vBGMap0 + 0x042, wBGMap0Copy + 0x042)
	ld hl, vBGMap0 + $042
	ld de, wBGMap0Copy + $042
	call CopyBoardRow
;> DrawScoreIfTypeA(vBGMap1 + 0x6D)
	ld hl, vBGMap1 + $6D
	call DrawScoreIfTypeA
;> hDrawBCDFlag = 1
	ld a, $01
	ldh [hDrawBCDFlag], a
	ret


;@ def RefreshBoardRow1()
;@ path: game/board_refresh
;@ Board refresh, stage $12: copies board row 1 from wBGMap0Copy to VRAM.
;@ reads: hBoardCopyStage
;@ writes: hBoardCopyStage
;@ Then redraws the score on BG map 0.
;@ test: hGameState = rng.choice([0, 1])
;@ test: hBoardCopyStage = rng.choice([$12, $12, 0])
;@ sig: b2360b17
RefreshBoardRow1::
;> if hBoardCopyStage != 0x12: return
	ldh a, [hBoardCopyStage]
	cp $12
	ret nz
;> CopyBoardRow(vBGMap0 + 0x022, wBGMap0Copy + 0x022)
	ld hl, vBGMap0 + $022
	ld de, wBGMap0Copy + $022
	call CopyBoardRow
;> DrawScoreIfTypeA(vBGMap0 + 0x6D)
	ld hl, vBGMap0 + $6D
	call DrawScoreIfTypeA
	ret


;@ def RefreshBoardRow0()
;@ path: game/board_refresh
;@ Board refresh, last stage ($13): copies board row 0, ends the refresh, then
;@ redraws the line counter and checks whether a type B game is won.
;@ reads: hBoardCopyStage, hTwoPlayer, hGameState, hGameType, hLines, hGarbageAdded, hTypeBLevel
;@ writes: wBoardCopyDone, hBoardCopyStage, hGarbageAdded, hTimer1, wMusicRequest, hVersusGoalReached, hGameState
;@ test: hBoardCopyStage = rng.choice([$13, $13, 0])
;@ test: hTwoPlayer = rng.choice([0, 0, 1])
;@ test: hGameState = rng.choice([0, 0, 0x1A, 3])
;@ sig: 01d62c8e
RefreshBoardRow0::
;> if hBoardCopyStage != 0x13: return
	ldh a, [hBoardCopyStage]
	cp $13
	ret nz

;> wBoardCopyDone = 0x13                   # any non-zero value
	ld [wBoardCopyDone], a
;> CopyBoardRow(vBGMap0 + 0x002, wBGMap0Copy + 0x002)
	ld hl, vBGMap0 + $002
	ld de, wBGMap0Copy + $002
	call CopyBoardRow
;> hBoardCopyStage = 0                     # refresh finished
	xor a
	ldh [hBoardCopyStage], a
;> if hTwoPlayer:
	ldh a, [hTwoPlayer]
	and a
	ldh a, [hGameState]
	jr nz, .twoPlayer

;>@tpstate     if hGameState != 0x1A: return
;>@tpgarbage     if hGarbageAdded:
;>@tpclear         hGarbageAdded = 0
;>@tpret         return
;> elif hGameState != 0: return
	and a
	ret nz

.drawLines
;> # draw the line counter
;> dest, src, n = vBGMap0 + 0x14E, addr(hLines) + 1, 2   # 4 digits: lines cleared
	ld hl, vBGMap0 + $14E
	ld de, hLines + 1
	ld c, $02
;> if hGameType != GAME_TYPE_A:
	ldh a, [hGameType]
	cp GAME_TYPE_A
	jr z, .draw

;>     dest, src, n = vBGMap0 + 0x150, addr(hLines), 1   # 2 digits: lines left
	ld hl, vBGMap0 + $150
	ld de, hLines
	ld c, $01

;> DrawBCD(src, dest, n)
.draw
	call DrawBCD
;> if hGameType == GAME_TYPE_A or lo(hLines) != 0:
	ldh a, [hGameType]
	cp GAME_TYPE_A
	jr z, .notWon

	ldh a, [hLines]
	and a
	jr nz, .notWon

;>@spawn     return SpawnNextPiece()
;> # type B: every line cleared - the game is won
;> hTimer1 = 100
	ld a, $64
	ldh [hTimer1], a
;> wMusicRequest = 2
	ld a, $02
	ld [wMusicRequest], a
;> if hTwoPlayer:
	ldh a, [hTwoPlayer]
	and a
	jr z, .onePlayerWon

;>     hVersusGoalReached = hTwoPlayer
	ldh [hVersusGoalReached], a
;>     return
	ret

;> state = 0x22 if hTypeBLevel == 9 else 0x05
.onePlayerWon
	ldh a, [hTypeBLevel]
	cp $09
	ld a, $05
	jr nz, .setState

	ld a, $22

;> hGameState = state
.setState
	ldh [hGameState], a
;> return
	ret

;=@spawn
.notWon
	call SpawnNextPiece
	ret

;=@tpstate
.twoPlayer
	cp $1a
	ret nz

;=@tpgarbage
	ldh a, [hGarbageAdded]
	and a
	jr z, .drawLines

;=@tpclear
	xor a
	ldh [hGarbageAdded], a
;=@tpret
	ret


;@ def DrawScoreIfTypeA(dest: hl)
;@ path: game/score
;@ Redraws the score at `dest` if it changed - only in game state 0 of a
;@ type A game.
;@ reads: hGameState, hGameType
;@ test: dest = rand(0x9800, 0x9BF0)
;@ test: hGameState = rng.choice([0, 0, 0, 1])
;@ test: hGameType = rng.choice([GAME_TYPE_A, GAME_TYPE_A, GAME_TYPE_B])
;@ test: hDrawBCDFlag = rng.choice([0, 1])
;@ sig: 6272b0ad
DrawScoreIfTypeA::
;> if hGameState != 0: return
	ldh a, [hGameState]
	and a
	ret nz

;> if hGameType != GAME_TYPE_A: return
	ldh a, [hGameType]
	cp GAME_TYPE_A
	ret nz

;> DrawBCDIfDirty(addr(wScore) + 2, dest)    # most significant byte first
	ld de, wScore + 2
	call DrawBCDIfDirty
	ret


;@ def CheckLevelUp()
;@ path: game/score
;@ Type A games (state 0): every 10 cleared lines the level goes up, up to 20.
;@ The new level is drawn on both BG maps, a sound plays and the pieces fall faster.
;@ reads: hGameState, hGameType, hLevel, hLines
;@ writes: hLevel, wSFXRequest
;@ test: hGameState = rng.choice([0, 0, 0, 1])
;@ test: hGameType = rng.choice([GAME_TYPE_A, GAME_TYPE_A, GAME_TYPE_B])
;@ test: hLevel = rand(0, 20)
;@ test: hLines = rand_bcd(2)
;@ sig: a4c271e3
CheckLevelUp::
;> if hGameState != 0: return
	ldh a, [hGameState]
	and a
	ret nz

;> if hGameType != GAME_TYPE_A: return
	ldh a, [hGameType]
	cp GAME_TYPE_A
	ret nz

;> if hLevel == 20: return
	ld hl, hLevel
	ld a, [hl]
	cp $14
	ret z

;> _, level = ByteToBCD(addr(hLevel))
	call ByteToBCD
;> if hi(hLines) >> 4: return                         # 1000 lines or more
	ldh a, [hLines + 1]
	ld d, a
	and $f0
	ret nz

;> tens = (hi(hLines) & 0x0F) << 4
	ld a, d
	and $0f
	swap a
	ld d, a
;> tens |= lo(hLines) >> 4                            # tens = lines / 10, as BCD
	ldh a, [hLines]
	and $f0
	swap a
	or d
;> if tens <= level: return
	cp b
	ret c

	ret z

;> hLevel += 1
	inc [hl]
;> _, level = ByteToBCD(addr(hLevel))
	call ByteToBCD
;> digit, pos = level & 0x0F, 0xF1                    # units digit first
	and $0f
	ld c, a
	ld hl, vBGMap0 + $F1

;>@draw while True:
;>     mem[vBGMap0 + pos] = digit                     # same tile on both BG maps
.drawDigit
	ld [hl], c
;>     mem[vBGMap1 + pos] = digit
	ld h, HIGH(vBGMap1)
	ld [hl], c
;>     if not level >> 4: break                       # no tens digit
	ld a, b
	and $f0
	jr z, .done

;>     digit = level >> 4
	swap a
	ld c, a
;>     if pos == 0xF0: break                          # tens digit drawn too
	ld a, l
	cp $f0
	jr z, .done

;>     pos = 0xF0
	ld hl, vBGMap0 + $F0
;=@draw
	jr .drawDigit

;> wSFXRequest = 8
.done
	ld a, $08
	ld [wSFXRequest], a
;> SetFallSpeed()
	call SetFallSpeed
;> return
	ret


;@ def ByteToBCD(ptr: hl) -> (a, b)
;@ path: lib/math
;@ Converts the byte at ptr (0-99) to packed BCD by counting up with daa.
;@ Returns the result in both a and b.
;@ test: ptr = rand_ram(1)
;@ sig: a5a3d94e
ByteToBCD::
;> value = mem[ptr]
	ld a, [hl]
	ld b, a
;> if value == 0: return 0, 0
	and a
	ret z

;> bcd = 0
	xor a

;>@count for _ in range(value):                  # count up in BCD
;>     bcd = to_bcd((bcd_to_int(bcd) + 1) % 100)
.count
	or a
	inc a
	daa
;=@count
	dec b
	jr z, .done

	jr .count

;> return bcd, bcd
.done
	ld b, a
	ret


;@ def CopyBoardRow(dest: hl, src: de)
;@ path: game/lines
;@ Copies one 10-tile board row from src to dest and moves hBoardCopyStage on.
;@ Only the low address bytes are incremented, so a row must not cross a
;@ 256-byte boundary (board rows never do).
;@ reads: hBoardCopyStage
;@ writes: hBoardCopyStage
;@ clobbers: a, b, e, l
;@ test: dest = (rand(0x9800, 0x9BFF) & 0xFFE0) | 2
;@ test: src = (rand(0xC800, 0xCBFF) & 0xFFE0) | 2
;@ sig: f49568f8
CopyBoardRow::
;> copy(dest, src, 10)
	ld b, $0a

.loop
	ld a, [de]
	ld [hl], a
	inc l
	inc e
	dec b
	jr nz, .loop

;> hBoardCopyStage += 1
	ldh a, [hBoardCopyStage]
	inc a
	ldh [hBoardCopyStage], a
;> return
	ret


;@ def HandlePieceInput()
;@ path: game/piece
;@ B and A rotate the falling piece (one rotation step forward / back), Left
;@ and Right move it, with autoshift: held, it moves again after 23 frames,
;@ then every 9. Every change is undone if the piece then collides.
;@ reads: wObjects, hJoyPressed, hJoyHeld, hAutoShiftTimer
;@ writes: hTemp, wObjects, wSFXRequest, hAutoShiftTimer
;@ test: hJoyPressed = rng.choice([0, BTN_A, BTN_B, BTN_RIGHT, BTN_LEFT, BTN_A | BTN_RIGHT])
;@ test: hJoyHeld = rng.choice([0, BTN_RIGHT, BTN_LEFT])
;@ test: hAutoShiftTimer = rand(1, 23)
;@ test: mem[0xC200] = rng.choice([0, 0, 0x80])
;@ test: mem[0xC201] = rand(0x18, 0x80)
;@ test: mem[0xC202] = rand(0x20, 0x60)
;@ test: mem[0xC203] = rand(0, 27)
;@ test: hObjHidden = 0
;@ test: for r in range(18): mem[0xC802 + 32 * r + rand(0, 9)] = rng.choice([0x2F, 0x80])
;@ sig: 14129a8d
HandlePieceInput::
;> if wObjects[0] == 0x80: return                  # no piece in play
	ld hl, wObjects
	ld a, [hl]
	cp $80
	ret z

;> hTemp = wObjects[3]
	ld l, $03
	ld a, [hl]
	ldh [hTemp], a
;> buttons = hJoyPressed
	ldh a, [hJoyPressed]
	ld b, a
;> if buttons & (BTN_A | BTN_B):
;>     if buttons & BTN_B:                          # B: one step forward
	bit 1, b
	jr nz, .turnB

;>@bif         if wObjects[3] & 3 != 3:
;>@binc             wObjects[3] += 1
;>@belse         else:
;>@bwrap             wObjects[3] &= 0xFC
;>     else:                                        # A: one step back (neither: on to the move)
	bit 0, b
	jr z, .move

;>         if wObjects[3] & 3:
	ld a, [hl]
	and $03
	jr z, .wrapA

;>             wObjects[3] -= 1
	dec [hl]
;>         else:
	jr .turned

;>             wObjects[3] |= 3
.wrapA
	ld a, [hl]
	or $03
	ld [hl], a
	jr .turned

;=@bif
.turnB
	ld a, [hl]
	and $03
	cp $03
	jr z, .wrapB

;=@binc
	inc [hl]
;=@belse
	jr .turned

;=@bwrap
.wrapB
	ld a, [hl]
	and $fc
	ld [hl], a

;>     wSFXRequest = 3
.turned
	ld a, $03
	ld [wSFXRequest], a
;>     DrawObject0()
	call DrawObject0
;>     if PieceCollides():                          # no room: undo the turn
	call PieceCollides
	and a
	jr z, .move

;>         wSFXRequest = 0
	xor a
	ld [wSFXRequest], a
;>         wObjects[3] = hTemp
	ld hl, wObjects + $03
	ldh a, [hTemp]
	ld [hl], a
;>         DrawObject0()
	call DrawObject0

;> pressed = hJoyPressed
.move
	ld hl, wObjects + $02
	ldh a, [hJoyPressed]
	ld b, a
;> held = hJoyHeld
	ldh a, [hJoyHeld]
	ld c, a
;> hTemp = wObjects[2]
	ld a, [hl]
	ldh [hTemp], a
;> timer = 23
;> if pressed & BTN_RIGHT or held & BTN_RIGHT:
	bit 4, b
	ld a, $17
	jr nz, .right

	bit 4, c
	jr z, .notRight

;>@rheld     if not pressed & BTN_RIGHT:              # held: autoshift (pressed jumps to .right)
;>         hAutoShiftTimer -= 1
	ldh a, [hAutoShiftTimer]
	dec a
	ldh [hAutoShiftTimer], a
;>         if hAutoShiftTimer: return
	ret nz

;>         timer = 9
	ld a, $09

;>     hAutoShiftTimer = timer
.right
	ldh [hAutoShiftTimer], a
;>     wObjects[2] += 8
	ld a, [hl]
	add $08
	ld [hl], a
;>     DrawObject0()
	call DrawObject0
;>     wSFXRequest = 4
	ld a, $04
	ld [wSFXRequest], a
;>@lif elif pressed & BTN_LEFT or held & BTN_LEFT:
;>@lheld     if not pressed & BTN_LEFT:               # held: autoshift (pressed jumps to .left)
;>@ldec         hAutoShiftTimer -= 1
;>@lret         if hAutoShiftTimer: return
;>@lnine         timer = 9
;>@lset     hAutoShiftTimer = timer
;>@lsub     wObjects[2] -= 8
;>@lsfx     wSFXRequest = 4
;>@ldraw     DrawObject0()
;>@else else:
;>@elseset     hAutoShiftTimer = 23
;>@elseret     return
;>@coll if PieceCollides():                         # no room: undo, retry next frame
	call PieceCollides
	and a
	ret z

;>     wSFXRequest = 0
.undoMove
	ld hl, wObjects + $02
	xor a
	ld [wSFXRequest], a
;>     wObjects[2] = hTemp
	ldh a, [hTemp]
	ld [hl], a
;>     DrawObject0()
	call DrawObject0
;>     hAutoShiftTimer = 1
	ld a, $01

.setTimer
	ldh [hAutoShiftTimer], a
;> return
	ret

;=@lif
.notRight
	bit 5, b
	ld a, $17
	jr nz, .left

	bit 5, c
;=@else
	jr z, .setTimer

;=@ldec
	ldh a, [hAutoShiftTimer]
	dec a
	ldh [hAutoShiftTimer], a
;=@lret
	ret nz

;=@lnine
	ld a, $09

;=@lset
.left
	ldh [hAutoShiftTimer], a
;=@lsub
	ld a, [hl]
	sub $08
	ld [hl], a
;=@lsfx
	ld a, $04
	ld [wSFXRequest], a
;=@ldraw
	call DrawObject0
;=@coll
	call PieceCollides
	and a
	ret z

	jr .undoMove

;@ def PieceCollides() -> a
;@ path: game/piece
;@ Checks the falling piece's 4 sprite tiles (shadow OAM entries 4-7) against
;@ the board in wBGMap0Copy. Returns 1 (and sets hCollision) when one of them
;@ sits on a non-blank tile.
;@ writes: hCoordY, hCoordX, hBGMapAddr, hCollision
;@ clobbers: b, de, hl
;@ test: for i in range(4): mem[0xC010 + 4 * i] = rand(0x18, 0xA0); mem[0xC011 + 4 * i] = rng.choice([0, rand(0x10, 0x60)])
;@ test: for r in range(18): mem[0xC802 + 32 * r + rand(0, 9)] = rng.choice([0x2F, 0x80])
;@ sig: 953d306a
PieceCollides::
;>@loop for i in range(4):
	ld hl, wShadowOAM + $10
	ld b, $04

;>     hCoordY = wShadowOAM[0x10 + 4 * i]
.loop
	ld a, [hli]
	ldh [hCoordY], a
;>     x = wShadowOAM[0x11 + 4 * i]
	ld a, [hli]
;>     if x == 0: break                              # unused entry: stop
	and a
	jr z, .free

;>     hCoordX = x
	ldh [hCoordX], a
;>     where = CoordsToBGMapAddr()
	push hl
	push bc
	call CoordsToBGMapAddr
;>     where += 0x3000                               # the same spot in wBGMap0Copy
	ld a, h
	add HIGH(wBGMap0Copy - vBGMap0)
	ld h, a
;>     if mem[where] != TILE_BLANK:
	ld a, [hl]
	cp TILE_BLANK
	jr nz, .blocked

;>@hit         hCollision = 1
;>@hitret         return 1
;=@loop
	pop bc
	pop hl
	inc l
	inc l
	dec b
	jr nz, .loop

;> hCollision = 0
.free
	xor a
	ldh [hCollision], a
;> return 0
	ret

;=@hit
.blocked
	pop bc
	pop hl
	ld a, $01
	ldh [hCollision], a
;=@hitret
	ret


;@ def LockPiece()
;@ path: game/piece
;@ Phase 1 (landed): writes the falling piece's tiles into the board - on BG
;@ map 0 (each write waits for HBlank) and into wBGMap0Copy - and hides the
;@ piece object. Then phase 2 (CheckLines).
;@ reads: hPiecePhase
;@ writes: hCoordY, hCoordX, hBGMapAddr, hPiecePhase, wObjects
;@ test: skip waits for the LCD
;@ sig: fd414856
LockPiece::
;> if hPiecePhase != 1: return
	ldh a, [hPiecePhase]
	cp $01
	ret nz

;>@loop for i in range(4):
	ld hl, wShadowOAM + $10
	ld b, $04

;>     hCoordY = wShadowOAM[0x10 + 4 * i]
.loop
	ld a, [hli]
	ldh [hCoordY], a
;>     x = wShadowOAM[0x11 + 4 * i]
	ld a, [hli]
;>     if x == 0: break
	and a
	jr z, .done

;>     hCoordX = x
	ldh [hCoordX], a
;>     where = CoordsToBGMapAddr()
	push hl
	push bc
	call CoordsToBGMapAddr
	push hl
	pop de
	pop bc
	pop hl

;>     wait_hblank()
.wait
	ldh a, [rSTAT]
	and $03
	jr nz, .wait

;>     mem[where] = wShadowOAM[0x12 + 4 * i]          # the sprite's tile
	ld a, [hl]
	ld [de], a
;>     mem[where + 0x3000] = wShadowOAM[0x12 + 4 * i] # and in wBGMap0Copy
	ld a, d
	add HIGH(wBGMap0Copy - vBGMap0)
	ld d, a
	ld a, [hli]
	ld [de], a
;=@loop
	inc l
	dec b
	jr nz, .loop

;> hPiecePhase = 2
.done
	ld a, $02
	ldh [hPiecePhase], a
;> wObjects[0] = 0x80                               # the tiles are in the BG now
	ld hl, wObjects
	ld [hl], $80
;> return
	ret


;@ def TallyCountStep(points: de, where: bc, entry: hl)
;@ path: game/tally
;@ One tally step for a line clear row. `entry` is its 5-byte counter: count,
;@ count shown (BCD), points (3 BCD bytes). Moves one clear from count to
;@ shown, adds its points to the row and the score; the next VBlank redraws
;@ the total. A finished row moves on to the next one.
;@ reads: wTallyStep, hTypeBLevel, wScoreTally
;@ writes: wTallyStep, wScore, wSFXRequest, wScoreTally
;@ test: points = rng.choice([0x0040, 0x0100, 0x0300, 0x1200])
;@ test: where = rng.choice([0x9823, 0x9883, 0x98E3, 0x9943])
;@ test: entry = 0xC0AC + 5 * rand(0, 3)
;@ test: wTallyStep = rng.choice([1, 1, 2])
;@ test: hTypeBLevel = rand(0, 9)
;@ test: for k in range(4): mem[0xC0AC + 5 * k] = rng.choice([0, 3]); mem[0xC0AD + 5 * k] = rand_bcd(1); fill_bcd(0xC0AE + 5 * k, 3)
;@ test: fill_bcd(0xC0A0, 3)
;@ sig: db0ee90e
TallyCountStep::
;> if wTallyStep == 2:                              # second frame: show the new total
	ld a, [wTallyStep]
	cp $02
	jr z, .total

;>@total     DrawBCD6(addr(wScore) + 2, vBGMap0 + 0x225)
;>@sfx     wSFXRequest = 2
;>@step0     wTallyStep = 0
;>@ret0     return
;> if mem[entry] == 0:                              # row done
	push de
	ld a, [hl]
	or a
	jr z, .rowDone

;>@next     return TallyNextRow()                   # (.rowDone falls through into it)
;> mem[entry] -= 1
	dec a
	ld [hli], a
;> shown = to_bcd((bcd_to_int(mem[entry + 1]) + 1) % 100)
	ld a, [hl]
	inc a
	daa
;> mem[entry + 1] = shown
	ld [hl], a
;> mem[where] = shown & 0x0F
	and $0f
	ld [bc], a
;> if shown >> 4:
	dec c
	ld a, [hli]
	swap a
	and $0f
	jr z, .points

;>     mem[where - 1] = shown >> 4
	ld [bc], a

;>@rowpts for _ in range(u8(hTypeBLevel + 1) or 256):
.points
	push bc
	ldh a, [hTypeBLevel]
	ld b, a
	inc b

;>     AddScoreBCD(points, entry + 2)               # the row's points
.rowPoints
	push hl
	call AddScoreBCD
	pop hl
;=@rowpts
	dec b
	jr nz, .rowPoints

;> src = entry + 4
	pop bc
	inc hl
	inc hl
;> DrawBCD6(src, where - 1 + 0x23)                  # the row's points, one line lower
	push hl
	ld hl, $0023
	add hl, bc
	pop de
	call DrawBCD6
;>@score for _ in range(u8(hTypeBLevel + 1) or 256):
	pop de
	ldh a, [hTypeBLevel]
	ld b, a
	inc b
	ld hl, wScore

;>     AddScoreBCD(points, addr(wScore))
.score
	push hl
	call AddScoreBCD
	pop hl
;=@score
	dec b
	jr nz, .score

;> wTallyStep = 2
	ld a, $02
	ld [wTallyStep], a
;> return
	ret

;=@total
.total
	ld de, wScore + 2
	ld hl, vBGMap0 + $225
	call DrawBCD6
;=@sfx
	ld a, $02
	ld [wSFXRequest], a
;=@step0
	xor a
	ld [wTallyStep], a
;=@ret0
	ret

;=@next
.rowDone
	pop de

;@ def TallyNextRow()
;@ path: game/tally
;@ Moves the type B tally to its next row; after the fifth one, state $04.
;@ reads: wTallyRow
;@ writes: hTimer1, wTallyStep, wTallyRow, hGameState
;@ test: wTallyRow = rand(0, 4)
;@ sig: 83dadd73
TallyNextRow::
;> hTimer1 = 0x21
	ld a, $21
	ldh [hTimer1], a
;> wTallyStep = 0
	xor a
	ld [wTallyStep], a
;> wTallyRow += 1
	ld a, [wTallyRow]
	inc a
	ld [wTallyRow], a
;> if wTallyRow != 5: return
	cp $05
	ret nz

;> hGameState = 0x04                                # State04_GameOverWait
	ld a, $04
	ldh [hGameState], a
;> return
	ret


;@ def ClearScoreData()
;@ path: game/setup
;@ Clears wScoreTally and the score.
;@ clobbers: a, b, hl
;@ sig: fa6c529e
ClearScoreData::
;> fill(wScoreTally, 0, 27)
	ld hl, wScoreTally
	ld b, $1b
	xor a

.clear
	ld [hli], a
	dec b
	jr nz, .clear

;> fill(wScore, 0, 3)
	ld hl, wScore
	ld b, $03

.clearScore
	ld [hli], a
	dec b
	jr nz, .clearScore

;> return
	ret

; unused code
	db $7e, $e6, $f0, $cb, $37, $12, $7e, $e6, $0f, $1c, $12, $c9

;@ def DrawTwoObjects()
;@ path: gfx/objects
;@ Draws the first two objects of wObjects into the start of the shadow OAM.
;@ test: for i in range(2): mem[0xC200 + 16 * i] = rng.choice([0, 0x80, 1])
;@ test: for i in range(2): mem[0xC203 + 16 * i] = rand(0, 0x5D)
;@ test: hObjHidden = 0
;@ sig: ee1268ae
DrawTwoObjects::
;> DrawObjectsAt0(2)                               # falls through
	ld a, $02

;@ def DrawObjectsAt0(count: a)
;@ path: gfx/objects
;@ Draws `count` objects from wObjects into the shadow OAM, from its start.
;@ writes: hObjCount, hOAMPtrHi, hOAMPtrLo
;@ test: count = rand(1, 4)
;@ test: for i in range(4): mem[0xC200 + 16 * i] = rng.choice([0, 0x80, 1])
;@ test: for i in range(4): mem[0xC203 + 16 * i] = rand(0, 0x5D)
;@ test: hObjHidden = 0
;@ sig: 41402e5b
DrawObjectsAt0::
;> hObjCount = count
	ldh [hObjCount], a
;> hOAMPtrLo = 0; hOAMPtrHi = hi(addr(wShadowOAM))
	xor a
	ldh [hOAMPtrLo], a
	ld a, HIGH(wShadowOAM)
	ldh [hOAMPtrHi], a
;> DrawObjects(addr(wObjects))
	ld hl, wObjects
	call DrawObjects
	ret


;@ def DrawObject0()
;@ path: gfx/objects
;@ Draws object 0 of wObjects into shadow OAM entries 4 and up ($C010).
;@ writes: hObjCount, hOAMPtrHi, hOAMPtrLo
;@ test: mem[0xC200] = rng.choice([0, 0x80, 1])
;@ test: mem[0xC203] = rand(0, 0x5D)
;@ test: hObjHidden = 0
;@ sig: 0232a271
DrawObject0::
;> hObjCount = 1
	ld a, $01
	ldh [hObjCount], a
;> hOAMPtrLo = 0x10; hOAMPtrHi = hi(addr(wShadowOAM))
	ld a, $10
	ldh [hOAMPtrLo], a
	ld a, HIGH(wShadowOAM)
	ldh [hOAMPtrHi], a
;> DrawObjects(addr(wObjects))
	ld hl, wObjects
	call DrawObjects
	ret


;@ def DrawObject1()
;@ path: gfx/objects
;@ Draws object 1 of wObjects into shadow OAM entries 8 and up ($C020).
;@ writes: hObjCount, hOAMPtrHi, hOAMPtrLo
;@ test: mem[0xC210] = rng.choice([0, 0x80, 1])
;@ test: mem[0xC213] = rand(0, 0x5D)
;@ test: hObjHidden = 0
;@ sig: aa32e45e
DrawObject1::
;> hObjCount = 1
	ld a, $01
	ldh [hObjCount], a
;> hOAMPtrLo = 0x20; hOAMPtrHi = hi(addr(wShadowOAM))
	ld a, $20
	ldh [hOAMPtrLo], a
	ld a, HIGH(wShadowOAM)
	ldh [hOAMPtrHi], a
;> DrawObjects(addr(wObjects) + 0x10)
	ld hl, wObjects + $10
	call DrawObjects
	ret


;@ def DrawWallColumn(top: hl)
;@ path: screens/title
;@ Writes a column of 32 wall tiles downwards from `top` (map rows are 32 bytes).
;@ clobbers: a, b, de, hl
;@ test: top = rand(0xC000, 0xC1FF)
;@ sig: 16091351
DrawWallColumn::
;>@loop for row in range(32):
	ld b, $20
	ld a, TILE_WALL
	ld de, $0020

;>     mem[top + 32 * row] = TILE_WALL
.loop
	ld [hl], a
;=@loop
	add hl, de
	dec b
	jr nz, .loop

;> return
	ret


;@ def CopyUntilFF(dest: hl, src: de)
;@ path: lib/memory
;@ Copies bytes from src to dest up to (not including) a $FF.
;@ clobbers: a, de, hl
;@ test: src = rand_ram(16)
;@ test: mem[src + rand(0, 15)] = 0xFF
;@ test: dest = rand_ram(16)
;@ sig: a49f2333
CopyUntilFF::
;>@loop while mem[src] != 0xFF:
	ld a, [de]
	cp $ff
	ret z

;>     mem[dest] = mem[src]
;>     dest += 1
	ld [hli], a
;>     src += 1
	inc de
;=@loop
	jr CopyUntilFF

;@ def TimerHandler()
;@ path: system/interrupts
;@ Shared target of the unused LCD STAT and timer interrupt vectors.
;@ test: skip interrupt handler (reti)
;@ sig: 2d0d85fd
TimerHandler::
;> return                                   # reti
	reti


; Object template for the falling piece (until $FF)
FallingPieceTemplate::
	db $00, $18, $3f, $00, $80, $00, $00, $ff

; Object template for the next piece preview (until $FF)
NextPieceTemplate::
	db $00, $80, $8f, $00, $80, $00, $00, $ff
; Initial objects for the game/music menu: 6 bytes each
MenuObjects::
	db $00, $70, $37, $1c, $00, $00, $00, $38, $37, $1c, $00, $00

; Initial object for the type A level select
TypeALevelMenuObjects::
	db $00, $40, $34, $20
	db $00, $00

; Initial objects for the type B level select
TypeBLevelMenuObjects::
	db $00, $40, $1c, $20, $00, $00, $00, $40, $74, $20, $00, $00

; The two height cursors of the 2-player menu
VersusMenuObjects::
	db $00, $40
	db $68, $21, $00, $00, $00, $78, $68, $21, $00, $00

; Objects shown when the master (Mario) won a round
VersusWinObjectsMaster::
	db $00, $60, $60, $2a, $80, $00
	db $00, $60, $72, $2a, $80, $20, $00, $68, $38, $3e, $80, $00

; Objects shown when the slave (Luigi) won a round
VersusWinObjectsSlave::
	db $00, $60, $60, $36
	db $80, $00, $00, $60, $72, $36, $80, $20, $00, $68, $38, $32, $80, $00

; Objects shown when the master (Mario) lost a round
VersusLoseObjectsMaster::
	db $00, $60
	db $60, $2e, $80, $00, $00, $68, $38, $3c, $80, $00

; Objects shown when the slave (Luigi) lost a round
VersusLoseObjectsSlave::
	db $00, $60, $60, $3a, $80, $00
	db $00, $68, $38, $30, $80, $00

; The 10 objects of the dancers ending (6 bytes each)
DancerObjects::
	db $80, $3f, $40, $44, $00, $00, $80, $3f, $20, $4a
	db $00, $00, $80, $3f, $30, $46, $00, $00, $80, $77, $20, $48, $00, $00, $80, $87
	db $48, $4c, $00, $00, $80, $87, $58, $4e, $00, $00, $80, $67, $4d, $50, $00, $00
	db $80, $67, $5d, $52, $00, $00, $80, $8f, $88, $54, $00, $00, $80, $8f, $98, $55
	db $00, $00

; Shuttle ending objects: the shuttle and two smoke clouds (6 bytes each)
ShuttleObjects::
	db $00, $5f, $57, $2c, $00, $00, $80, $80, $50, $34, $00, $00, $80, $80
	db $60, $34, $00, $20

; Rocket ending objects: the rocket and two smoke clouds (6 bytes each)
RocketObjects::
	db $00, $6f, $57, $58, $00, $00, $80, $80, $55, $34, $00, $00
	db $80, $80, $5b, $34, $00, $20

;@ def ClearBGMap0()
;@ path: gfx/tilemaps
;@ Fills BG map 0 with blank tiles.
;@ clobbers: a, bc, hl
;@ sig: 3237427b
ClearBGMap0::
;> ClearTilemap(vBGMap0 + 0x3FF)            # falls through
	ld hl, vBGMap0 + $3FF

;@ def ClearTilemap(last: hl)
;@ path: gfx/tilemaps
;@ Fills the 32x32 tile map that ends at `last` with TILE_BLANK, back to front.
;@ clobbers: a, bc, hl
;@ test: last = rand(0x83FF, 0xDDFF)
;@ sig: 10f9d0c8
ClearTilemap::
;>@loop for i in range(0x400):
	ld bc, $0400

;>     mem[last - i] = TILE_BLANK
.loop
	ld a, TILE_BLANK
	ld [hld], a
;=@loop
	dec bc
	ld a, b
	or c
	jr nz, .loop

;> return
	ret


;@ def CopyBytes(src: hl, dest: de, count: bc)
;@ path: lib/memory
;@ Copies `count` bytes from src to dest, front to back.
;@ A count of 0 copies 64 KiB.
;@ clobbers: a, bc, de, hl
;@ test: count = rand(1, 0x100)
;@ test: src = rand(0x0000, 0xDE00)
;@ test: dest = rand_ram(count)
;@ sig: 994589e5
CopyBytes::
;>@loop for i in range(count or 0x10000):
;>     mem[dest + i] = mem[src + i]
	ld a, [hli]
	ld [de], a
	inc de
;=@loop
	dec bc
	ld a, b
	or c
	jr nz, CopyBytes

;> return
	ret


;@ def LoadGameTiles()
;@ path: gfx/tiles
;@ Tiles for the menus and the game: the font, the first $A0 bytes of
;@ TitleTiles behind it, then GameTiles at $8300.
;@ clobbers: a, bc, de, hl
;@ sig: 73623dc5
LoadGameTiles::
;> src, dest = LoadFont()
	call LoadFont
;> CopyBytes(src, dest, 0xA0)
	ld bc, $00a0
	call CopyBytes
;> CopyBytes(GameTiles, vTiles0 + 0x300, 0xD00)
	ld hl, GameTiles
	ld de, $8300
	ld bc, $0d00
	call CopyBytes
;> return
	ret


;@ def LoadFont() -> (hl, de)
;@ path: gfx/tiles
;@ Expands the 1-bit-per-pixel font at Font1bpp into 2bpp tiles at vTiles0.
;@ Every byte is written to both bit planes, so pixels are colour 0 or 3.
;@ Returns the end of the source and the destination, which callers use to
;@ continue copying the tiles that follow.
;@ clobbers: a, bc
;@ sig: 3b5d4f9a
LoadFont::
;>@loop for i in range(0x138):
	ld hl, Font1bpp
	ld bc, $0138
	ld de, vTiles0

;>     mem[vTiles0 + 2 * i] = mem[Font1bpp + i]          # both bit planes
.loop
	ld a, [hli]
	ld [de], a
	inc de
;>     mem[vTiles0 + 2 * i + 1] = mem[Font1bpp + i]
	ld [de], a
	inc de
;=@loop
	dec bc
	ld a, b
	or c
	jr nz, .loop

;> return Font1bpp + 0x138, vTiles0 + 2 * 0x138
	ret


;@ def LoadTitleTiles()
;@ path: gfx/tiles
;@ Tiles for the copyright and title screens: the font, then $DA0 bytes of
;@ TitleTiles right behind it.
;@ clobbers: a, bc, de, hl
;@ sig: 06d77b8f
LoadTitleTiles::
;> src, dest = LoadFont()
	call LoadFont
;> CopyBytes(src, dest, 0xDA0)
	ld bc, $0da0
	call CopyBytes
	ret

; unused: ld bc, $1000 (an entry to LoadTilesToVRAM with a fixed size)
	db $01, $00, $10

;@ def LoadTilesToVRAM(src: hl, count: bc)
;@ path: gfx/tiles
;@ Copies `count` bytes of tile data from src to the start of VRAM.
;@ clobbers: a, bc, de, hl
;@ test: src = rand(0x0000, 0x7000)
;@ test: count = rand(1, 0x200)
;@ sig: 62070f33
LoadTilesToVRAM::
;> CopyBytes(src, vTiles0, count)                  # falls through to DoNothing's ret
	ld de, vTiles0
	call CopyBytes

;@ def DoNothing()
;@ path: boot
;@ A lone `ret`. Used as the empty entry in the state jump tables.
;@ sig: 30ba9599
DoNothing::
;> return
	ret


;@ def LoadScreen(src: de) -> de
;@ path: gfx/tilemaps
;@ Copies a full 20x18 tile screen from src to the top-left of BG map 0.
;@ clobbers: a, bc, hl
;@ test: src = rand(0x0000, 0x7000)
;@ sig: 381aeeb3
LoadScreen::
;> return LoadScreenAt(src, vBGMap0)        # falls through
	ld hl, vBGMap0

;@ def LoadScreenAt(src: de, dest: hl) -> de
;@ path: gfx/tilemaps
;@ Copies a full 20x18 tile screen from src into the BG map at dest.
;@ clobbers: a, bc, hl
;@ test: src = rand(0x0000, 0x7000)
;@ test: dest = rand(0x8000, 0xDA00)
;@ sig: e43ac431
LoadScreenAt::
;> return CopyTilemapRows(src, dest, 18)    # falls through
	ld b, $12

;@ def CopyTilemapRows(src: de, dest: hl, rows: b) -> de
;@ path: gfx/tilemaps
;@ Copies `rows` rows of 20 tiles from src into the BG map at dest. BG map
;@ rows are 32 tiles apart. Returns the end of the source data.
;@ clobbers: a, bc, hl
;@ test: rows = rand(1, 18)
;@ test: src = rand(0x0000, 0x7000)
;@ test: dest = rand(0x8000, 0xDA00)
;@ sig: 10e6fe2f
CopyTilemapRows::
;>@rows for _ in range(rows):
	push hl
;>@col     for col in range(20):
	ld c, $14

;>         mem[dest + col] = mem[src]
.copyRow
	ld a, [de]
	ld [hli], a
;>         src += 1
	inc de
;=@col
	dec c
	jr nz, .copyRow

;>     dest += 32                                   # next BG map row
	pop hl
	push de
	ld de, $0020
	add hl, de
	pop de
;=@rows
	dec b
	jr nz, CopyTilemapRows

;> return src
	ret


;@ def CopyTilemapBlock(src: de, dest: hl)
;@ path: gfx/tilemaps
;@ Copies rows of 10 tiles from src into the BG map at dest until it reads
;@ a $FF terminator, then sets hBoardCopyStage to 2.
;@ writes: hBoardCopyStage
;@ clobbers: a, b, de, hl
;@ test: src = rand_ram(64)
;@ test: mem[src + rand(0, 63)] = 0xFF
;@ test: dest = rand(0x8000, 0x9000)
;@ sig: a2515984
CopyTilemapBlock::
;>@row while True:                                 # one BG map row per pass
;=@col
	ld b, $0a
;>     row_start = dest
	push hl

;>@col     for x in range(10):
;>         tile = mem[src]
.loop
	ld a, [de]
;>         if tile == 0xFF:
	cp $ff
	jr z, .done

;>@fin             hBoardCopyStage = 2
;>@finret             return
;>         mem[row_start + x] = tile
	ld [hli], a
;>         src += 1
	inc de
;=@col
	dec b
	jr nz, .loop

;>     dest = row_start + 32                        # next BG map row
	pop hl
	push de
	ld de, $0020
	add hl, de
	pop de
;=@row
	jr CopyTilemapBlock

;=@fin
.done
	pop hl
	ld a, $02
	ldh [hBoardCopyStage], a
;=@finret
	ret


;@ def DisableLCD()
;@ path: system/lcd
;@ Waits for VBlank and switches the LCD off. The VBlank interrupt is
;@ masked while waiting so the handler can't run in between.
;@ writes: hSavedIE
;@ test: skip polls the LCD
;@ sig: 16a2cd7a
DisableLCD::
;> hSavedIE = rIE
	ldh a, [rIE]
	ldh [hSavedIE], a
;> rIE = hSavedIE & ~1                       # no VBlank interrupt for now
	res 0, a
	ldh [rIE], a

;> wait_ly(0x91)                             # inside VBlank
.waitVBlank
	ldh a, [rLY]
	cp $91
	jr nz, .waitVBlank

;> rLCDC &= 0x7F                             # LCD off
	ldh a, [rLCDC]
	and $7f
	ldh [rLCDC], a
;> rIE = hSavedIE
	ldh a, [hSavedIE]
	ldh [rIE], a
	ret


;@ asset: tilemap width=8 height=10 tiles=LoadGameTiles
;@ Text drawn over the board on BG map 1, which is shown while paused.
PauseScreenText::
	db $2f, $2f, $11, $12, $1d, $2f, $2f, $2f, $2f, $2f, $29, $29, $29, $2f, $2f, $2f
	db $2f, $1c, $1d, $0a, $1b, $1d, $2f, $2f, $2f, $29, $29, $29, $29, $29, $2f, $2f
	db $2f, $2f, $2f, $1d, $18, $2f, $2f, $2f, $2f, $2f, $2f, $29, $29, $2f, $2f, $2f
	db $0c, $18, $17, $1d, $12, $17, $1e, $0e, $29, $29, $29, $29, $29, $29, $29, $29
	db $2f, $2f, $10, $0a, $16, $0e, $2f, $2f, $2f, $2f, $29, $29, $29, $29, $2f, $2f
; Type B result screen text for the board (10 x 18 tiles)
TypeBTallyText::
	db $1c, $12, $17, $10, $15, $0e, $2f, $2f, $2f, $2f, $2f, $00, $2f, $26, $2f, $04
	db $00, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $00, $2f, $0d, $18
	db $1e, $0b, $15, $0e, $2f, $2f, $2f, $2f, $2f, $00, $2f, $26, $2f, $01, $00, $00
	db $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $00, $2f, $1d, $1b, $12, $19
	db $15, $0e, $2f, $2f, $2f, $2f, $2f, $00, $2f, $26, $2f, $03, $00, $00, $2f, $2f
	db $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $00, $2f, $1d, $0e, $1d, $1b, $12, $1c
	db $2f, $2f, $2f, $2f, $2f, $00, $2f, $26, $2f, $01, $02, $00, $00, $2f, $2f, $2f
	db $2f, $2f, $2f, $2f, $2f, $2f, $00, $2f, $0d, $1b, $18, $19, $1c, $2f, $2f, $2f
	db $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $00, $2f, $2f, $2f, $2f, $2f
	db $2f, $2f, $2f, $2f, $2f, $2f, $29, $29, $29, $29, $29, $29, $29, $29, $29, $29
	db $1d, $11, $12, $1c, $2f, $1c, $1d, $0a, $10, $0e, $2f, $2f, $2f, $2f, $2f, $2f
	db $2f, $2f, $00, $2f, $ff

; GAME OVER box (8 x 7 tiles)
GameOverText::
	db $61, $62, $62, $62, $62, $62, $62, $63, $64, $2f, $2f
	db $2f, $2f, $2f, $2f, $65, $64, $2f, $10, $0a, $16, $0e, $2f, $65, $64, $2f, $ad
	db $ad, $ad, $ad, $2f, $65, $64, $2f, $18, $1f, $0e, $1b, $2f, $65, $64, $2f, $ad
	db $ad, $ad, $ad, $2f, $65, $66, $69, $69, $69, $69, $69, $69, $6a

; PLEASE TRY AGAIN box (8 x 6 tiles)
TryAgainText::
	db $19, $15, $0e
	db $0a, $1c, $0e, $2f, $2f, $29, $29, $29, $29, $29, $29, $2f, $2f, $2f, $1d, $1b
	db $22, $2f, $2f, $2f, $2f, $2f, $29, $29, $29, $2f, $2f, $2f, $2f, $2f, $2f, $0a
	db $10, $0a, $12, $17, $27, $2f, $2f, $29, $29, $29, $29, $29, $2f

;@ def ReadJoypad()
;@ path: system/input
;@ Reads all eight buttons into hJoyHeld and works out which of them were
;@ pressed since the last call (hJoyPressed).
;@ reads: hJoyHeld
;@ writes: hJoyHeld, hJoyPressed
;@ clobbers: a, b, c
;@ sig: a0c59ef9
ReadJoypad::
;> rP1 = 0x20                                  # select the d-pad
	ld a, $20
	ldh [rP1], a
;> pins = rP1                                  # read 4 times to let the lines settle
	ldh a, [rP1]
	ldh a, [rP1]
	ldh a, [rP1]
	ldh a, [rP1]
;> dpad = (~pins & 0x0F) << 4
	cpl
	and $0f
	swap a
	ld b, a
;> rP1 = 0x10                                  # select A/B/Select/Start
	ld a, $10
	ldh [rP1], a
;> pins = rP1                                  # read 10 times
	ldh a, [rP1]
	ldh a, [rP1]
	ldh a, [rP1]
	ldh a, [rP1]
	ldh a, [rP1]
	ldh a, [rP1]
	ldh a, [rP1]
	ldh a, [rP1]
	ldh a, [rP1]
	ldh a, [rP1]
;> buttons = ~pins & 0x0F
	cpl
	and $0f
;> held = dpad | buttons
	or b
	ld c, a
;> hJoyPressed = held & ~hJoyHeld              # down now, but not last time
	ldh a, [hJoyHeld]
	xor c
	and c
	ldh [hJoyPressed], a
;> hJoyHeld = held
	ld a, c
	ldh [hJoyHeld], a
;> rP1 = 0x30                                  # deselect both groups
	ld a, $30
	ldh [rP1], a
;> return
	ret


;@ def CoordsToBGMapAddr() -> hl
;@ path: gfx/tilemaps
;@ Converts the OAM-space coordinates (hCoordY, hCoordX) into the address
;@ of the BG map 0 tile under them. Stores it in hBGMapAddr and returns it.
;@ reads: hCoordY, hCoordX
;@ writes: hBGMapAddr
;@ clobbers: a, b, de
;@ sig: 30eb7feb
CoordsToBGMapAddr::
;> row = u8(hCoordY - 16) // 8                # sub wraps around below 16
	ldh a, [hCoordY]
	sub $10
	srl a
	srl a
	srl a
;> tile_addr = vBGMap0
	ld de, $0000
	ld e, a
	ld hl, vBGMap0
;>@mul for _ in range(32):                       # tile_addr = vBGMap0 + 32 * row
	ld b, $20

;>     tile_addr += row
.multiply
	add hl, de
;=@mul
	dec b
	jr nz, .multiply

;> col = u8(hCoordX - 8) // 8
	ldh a, [hCoordX]
	sub $08
	srl a
	srl a
	srl a
;> tile_addr += col
	ld de, $0000
	ld e, a
	add hl, de
;> hBGMapAddr = tile_addr
	ld a, h
	ldh [hBGMapAddr + 1], a
	ld a, l
	ldh [hBGMapAddr], a
;> return tile_addr
	ret


	db $f0, $b5, $57, $f0, $b4, $5f, $06, $04, $cb, $1a, $cb, $1b, $05, $20, $f9, $7b
	db $d6, $84, $e6, $fe, $07, $07, $c6, $08, $e0, $b2, $f0, $b4, $e6, $1f, $17, $17
	db $17, $c6, $08, $e0, $b3, $c9

;@ def DrawBCDIfDirty(src: de, dest: hl)
;@ path: gfx/numbers
;@ Draws a 6-digit BCD number (see DrawBCD) if hDrawBCDFlag is set.
;@ reads: hDrawBCDFlag
;@ writes: hDrawBCDFlag
;@ clobbers: a, bc, e, hl
;@ test: src = rand_ram(8) + 4
;@ test: dest = rand(0x9800, 0x9BF0)
;@ test: hDrawBCDFlag = rng.choice([0, 1])
;@ sig: 7a3979b7
DrawBCDIfDirty::
;> if not hDrawBCDFlag: return
	ldh a, [hDrawBCDFlag]
	and a
	ret z

;> DrawBCD6(src, dest)                      # falls through
;@ def DrawBCD6(src: de, dest: hl)
;@ path: gfx/numbers
;@ Draws a 6-digit (3-byte) BCD number, see DrawBCD.
;@ writes: hDrawBCDFlag
;@ clobbers: a, bc, e, hl
;@ test: src = rand_ram(8) + 4
;@ test: dest = rand(0x9800, 0x9BF0)
;@ sig: 46536ecb
DrawBCD6::
;> DrawBCD(src, dest, 3)                    # falls through
	ld c, $03

;@ def DrawBCD(src: de, dest: hl, nbytes: c)
;@ path: gfx/numbers
;@ Draws a packed BCD number of `nbytes` bytes as digit tiles (tile n shows
;@ digit n) at dest. The most significant byte is at src, the others below
;@ it. Leading zeros are drawn blank, but the last digit is always drawn.
;@ writes: hDrawBCDFlag
;@ clobbers: a, bc, e, hl
;@ test: nbytes = rand(1, 4)
;@ test: src = rand_ram(8) + 4
;@ test: dest = rand(0x9800, 0x9BF0)
;@ sig: 1398cd42
DrawBCD::
;> hDrawBCDFlag = 0                         # becomes 1 once a digit is drawn
	xor a
	ldh [hDrawBCDFlag], a

.loop
;>@loop for i in range(nbytes):
;>     byte = mem[hi(src) << 8 | lo(src - i)]   # only E is decremented
	ld a, [de]
	ld b, a
;>     if byte >> 4:
	swap a
	and $0f
	jr nz, .highDigit

;>@hflag         hDrawBCDFlag = 1                     # (out of line)
;>@htile         tile = byte >> 4
;>     elif hDrawBCDFlag:
;>         tile = 0
	ldh a, [hDrawBCDFlag]
	and a
	ld a, $00
	jr nz, .drawHigh

;>     else:
;>         tile = TILE_BLANK                        # leading zero
	ld a, TILE_BLANK

;>     mem[dest] = tile
;>     dest += 1
.drawHigh
	ld [hli], a
;>     if byte & 0x0F:
	ld a, b
	and $0f
	jr nz, .lowDigit

;>@lflag         hDrawBCDFlag = 1                     # (out of line)
;>@ltile         tile = byte & 0x0F
;>     elif hDrawBCDFlag:
;>         tile = 0
	ldh a, [hDrawBCDFlag]
	and a
	ld a, $00
	jr nz, .drawLow

;>     elif i == nbytes - 1:                        # the last digit is always drawn
;>         tile = 0
	ld a, $01
	cp c
	ld a, $00
	jr z, .drawLow

;>     else:
;>         tile = TILE_BLANK
	ld a, TILE_BLANK

;>     mem[dest] = tile
;>     dest += 1
.drawLow
	ld [hli], a
;=@loop
	dec e
	dec c
	jr nz, .loop

;> hDrawBCDFlag = 0
	xor a
	ldh [hDrawBCDFlag], a
;> return
	ret


;=@hflag
.highDigit
	push af
	ld a, $01
	ldh [hDrawBCDFlag], a
	pop af
;=@htile
	jr .drawHigh

;=@lflag
.lowDigit
	push af
	ld a, $01
	ldh [hDrawBCDFlag], a
	pop af
;=@ltile
	jr .drawLow

; Copied to hOAMDMA at boot and run from there: the CPU can only see HRAM
; while an OAM DMA transfer is running.
;@ def OAMDMARoutine()
;@ path: system/lcd
;@ Copies the shadow OAM (wShadowOAM) to OAM with a DMA transfer.
;@ test: skip runs from HRAM, needs the DMA hardware
;@ sig: 3f1b3df7
OAMDMARoutine::
;> rDMA = hi(addr(wShadowOAM))         # start the DMA transfer
	ld a, HIGH(wShadowOAM)
	ldh [rDMA], a
;> # wait 160 cycles for the transfer to finish
	ld a, $28
.wait
	dec a
	jr nz, .wait
	ret


;@ def DrawObjects(obj: hl)
;@ path: gfx/objects
;@ The metasprite engine. Draws hObjCount objects (16 bytes each, starting at
;@ `obj`) into the shadow OAM at hOAMPtrHi:hOAMPtrLo, moving that pointer on.
;@ An object's sprite id picks a sprite from SpriteTable: a list of tiles
;@ placed on a grid of (y, x) offsets, where $FE leaves a cell empty, $FD
;@ mirrors the next tile and $FF ends the list.
;@ reads: hObjCount, hOAMPtrHi, hOAMPtrLo, hObjHidden
;@ writes: hObjState, hObjY, hObjX, hObjSprite, hObjAttrBits, hObjFlip, hObjAttr, hSpriteYOff, hSpriteXOff, hTileX, hTileY, hTileAttr, hObjHidden, hObjPtrHi, hObjPtrLo, hObjCount, hOAMPtrHi, hOAMPtrLo
;@ test: obj = 0xC200
;@ test: hObjCount = rand(1, 4)
;@ test: hOAMPtrHi = 0xC0
;@ test: hOAMPtrLo = 0
;@ test: hObjHidden = 0
;@ test: for i in range(4): mem[0xC200 + 16 * i] = rng.choice([0, 0, 0x80, 1])
;@ test: for i in range(4): mem[0xC203 + 16 * i] = rand(0, 0x5D)
;@ sig: 664d49fb
DrawObjects::
;>@obj while True:
;>     hObjPtrHi = hi(obj)
	ld a, h
	ldh [hObjPtrHi], a
;>     hObjPtrLo = lo(obj)
	ld a, l
	ldh [hObjPtrLo], a
;>     if mem[obj] in (0x00, 0x80):                  # any other state: not drawn
	ld a, [hl]
	and a
	jr z, .draw

	cp $80
	jr z, .hidden

;=@ptr
.next
	ldh a, [hObjPtrHi]
	ld h, a
	ldh a, [hObjPtrLo]
	ld l, a
;=@add16
	ld de, $0010
	add hl, de
;=@count
	ldh a, [hObjCount]
	dec a
	ldh [hObjCount], a
;=@done
	ret z

;=@obj
	jr DrawObjects

;=@end0
.endOfSprite
	xor a
	ldh [hObjHidden], a
;=@endbrk
	jr .next

;>         if mem[obj] == 0x80: hObjHidden = 0x80     # hidden: its tiles get Y = $FF
.hidden
	ldh [hObjHidden], a

;>@copy         for k in range(7):                        # hObjState ... hObjAttr
.draw
	ld b, $07
	ld de, hObjState

;>             mem[addr(hObjState) + k] = mem[obj + k]
.copy
	ld a, [hli]
	ld [de], a
	inc de
;=@copy
	dec b
	jr nz, .copy

;>         entry = SpriteTable + 2 * hObjSprite
	ldh a, [hObjSprite]
	ld hl, SpriteTable
	rlca
	ld e, a
	ld d, $00
	add hl, de
;>         header = mem16[entry]
	ld e, [hl]
	inc hl
	ld d, [hl]
;>         tiles = mem16[header]
	ld a, [de]
	ld l, a
	inc de
	ld a, [de]
	ld h, a
;>         hSpriteYOff = mem[header + 2]
	inc de
	ld a, [de]
	ldh [hSpriteYOff], a
;>         hSpriteXOff = mem[header + 3]
	inc de
	ld a, [de]
	ldh [hSpriteXOff], a
;>         offsets = mem16[tiles]                    # a (y, x) pair per grid cell
;>         p = tiles + 1
	ld e, [hl]
	inc hl
	ld d, [hl]

;>@tile         while True:
;>             p += 1
.nextTile
	inc hl
;>             hTileAttr = hObjAttr
	ldh a, [hObjAttr]
	ldh [hTileAttr], a
;>             tile = mem[p]
	ld a, [hl]
;>             if tile == 0xFF:
	cp $ff
	jr z, .endOfSprite

;>@end0                 hObjHidden = 0
;>@endbrk                 break
;>             if tile == 0xFD:                      # mirror the next tile
	cp $fd
	jr nz, .notMirrored

;>                 hTileAttr = hObjAttr ^ 0x20
	ldh a, [hObjAttr]
	xor $20
	ldh [hTileAttr], a
;>                 p += 1
	inc hl
;>                 tile = mem[p]
	ld a, [hl]
;>@elif             elif tile == 0xFE:                    # empty cell
;>@skip                 offsets += 2
;>@cont                 continue
;=@elif
	jr .emit

;=@skip
.skipCell
	inc de
	inc de
;=@cont
	jr .nextTile

;=@elif
.notMirrored
	cp $fe
	jr z, .skipCell

;>             hObjSprite = tile
.emit
	ldh [hObjSprite], a
;>             cell_y = mem[offsets]
	ldh a, [hObjY]
	ld b, a
	ld a, [de]
	ld c, a
;>             if not hObjFlip & 0x40:
	ldh a, [hObjFlip]
	bit 6, a
	jr nz, .flipY

;>                 s = hSpriteYOff + hObjY
	ldh a, [hSpriteYOff]
	add b
;>                 y = s + cell_y + (s > 0xFF)      # adc: the first carry counts too
	adc c
;>             else:                                 # flipped vertically
	jr .storeY

;>                 d = hObjY - hSpriteYOff
.flipY
	ld a, b
	push af
	ldh a, [hSpriteYOff]
	ld b, a
	pop af
	sub b
;>                 d2 = u8(d) - cell_y - (d < 0)
	sbc c
;>                 y = d2 - 8 - (d2 < 0)
	sbc $08

;>             hTileY = y
.storeY
	ldh [hTileY], a
;>@cellx             cell_x = mem[offsets + 1]
	ldh a, [hObjX]
	ld b, a
	inc de
	ld a, [de]
;>             offsets += 2
	inc de
;=@cellx
	ld c, a
;>             if not hObjFlip & 0x20:
	ldh a, [hObjFlip]
	bit 5, a
	jr nz, .flipX

;>                 s = hSpriteXOff + hObjX
	ldh a, [hSpriteXOff]
	add b
;>                 x = s + cell_x + (s > 0xFF)
	adc c
;>             else:                                 # flipped horizontally
	jr .storeX

;>                 d = hObjX - hSpriteXOff
.flipX
	ld a, b
	push af
	ldh a, [hSpriteXOff]
	ld b, a
	pop af
	sub b
;>                 d2 = u8(d) - cell_x - (d < 0)
	sbc c
;>                 x = d2 - 8 - (d2 < 0)
	sbc $08

;>             hTileX = x
.storeX
	ldh [hTileX], a
;>             oam = hOAMPtrHi << 8 | hOAMPtrLo
	push hl
	ldh a, [hOAMPtrHi]
	ld h, a
	ldh a, [hOAMPtrLo]
	ld l, a
;>             if hObjHidden:
	ldh a, [hObjHidden]
	and a
	jr z, .visible

;>                 oam_y = 0xFF
	ld a, $ff
;>             else:
	jr .writeY

;>                 oam_y = hTileY
.visible
	ldh a, [hTileY]

;>             mem[oam] = oam_y
.writeY
	ld [hli], a
;>             mem[oam + 1] = hTileX
	ldh a, [hTileX]
	ld [hli], a
;>             mem[oam + 2] = hObjSprite
	ldh a, [hObjSprite]
	ld [hli], a
;>             attr = hTileAttr | hObjFlip
	ldh a, [hTileAttr]
	ld b, a
	ldh a, [hObjFlip]
	or b
	ld b, a
;>             mem[oam + 3] = attr | hObjAttrBits
	ldh a, [hObjAttrBits]
	or b
	ld [hli], a
;>             hOAMPtrHi = hi(oam + 4)
	ld a, h
	ldh [hOAMPtrHi], a
;>             hOAMPtrLo = lo(oam + 4)
	ld a, l
	ldh [hOAMPtrLo], a
;=@tile
	pop hl
	jp .nextTile

;>@ptr     obj = hObjPtrHi << 8 | hObjPtrLo
;>@add16     obj += 16
;>@count     hObjCount -= 1
;>@done     if hObjCount == 0: return

;@ asset: sprites count=$5E tiles=LoadGameTiles|LoadTitleTiles|LoadTilesToVRAM(hl=CutsceneTiles,bc=$1000)
;@ All sprites (metasprites) the object engine can draw, indexed by sprite id.
;@ Each one is drawn here by running DrawObjects in the emulator.
SpriteTable::
	db $20, $2c, $24, $2c, $28, $2c, $2c, $2c, $30, $2c, $34, $2c, $38, $2c, $3c, $2c
	db $40, $2c, $44, $2c, $48, $2c, $4c, $2c, $50, $2c, $54, $2c, $58, $2c, $5c, $2c
	db $60, $2c, $64, $2c, $68, $2c, $6c, $2c, $70, $2c, $74, $2c, $78, $2c, $7c, $2c
	db $80, $2c, $84, $2c, $88, $2c, $8c, $2c, $90, $2c, $94, $2c, $98, $2c, $9c, $2c
	db $a0, $2c, $a4, $2c, $a8, $2c, $ac, $2c, $b0, $2c, $b4, $2c, $b8, $2c, $bc, $2c
	db $c0, $2c, $c4, $2c, $c8, $2c, $cc, $2c, $c7, $30, $cc, $2c, $d0, $2c, $d4, $2c
	db $d8, $2c, $dc, $2c, $e0, $2c, $e4, $2c, $ea, $30, $ee, $30, $e8, $2c, $ec, $2c
	db $f2, $30, $f6, $30, $f0, $2c, $f4, $2c, $f8, $2c, $fc, $2c, $00, $2d, $04, $2d
	db $fa, $30, $fe, $30, $04, $2d, $08, $2d, $08, $2d, $0c, $2d, $10, $2d, $14, $2d
	db $18, $2d, $1c, $2d, $20, $2d, $24, $2d, $28, $2d, $2c, $2d, $30, $2d, $34, $2d
	db $38, $2d, $3c, $2d, $40, $2d, $44, $2d, $48, $2d, $4c, $2d, $50, $2d, $54, $2d
	db $0a, $31, $0e, $31, $12, $31, $12, $31, $02, $31, $06, $31

; Sprite headers: tile list pointer, Y offset, X offset
SpriteHeaders::
	db $58, $2d, $ef, $f0
	db $68, $2d, $ef, $f0, $7a, $2d, $ef, $f0, $89, $2d, $ef, $f0, $9a, $2d, $ef, $f0
	db $ac, $2d, $ef, $f0, $bd, $2d, $ef, $f0, $cb, $2d, $ef, $f0, $dc, $2d, $ef, $f0
	db $eb, $2d, $ef, $f0, $fc, $2d, $ef, $f0, $0b, $2e, $ef, $f0, $1c, $2e, $ef, $f0
	db $2e, $2e, $ef, $f0, $40, $2e, $ef, $f0, $52, $2e, $ef, $f0, $64, $2e, $ef, $f0
	db $76, $2e, $ef, $f0, $86, $2e, $ef, $f0, $98, $2e, $ef, $f0, $a8, $2e, $ef, $f0
	db $b9, $2e, $ef, $f0, $ca, $2e, $ef, $f0, $db, $2e, $ef, $f0, $0b, $2f, $ef, $f0
	db $1c, $2f, $ef, $f0, $ec, $2e, $ef, $f0, $fa, $2e, $ef, $f0, $2d, $2f, $00, $e8
	db $36, $2f, $00, $e8, $3f, $2f, $00, $e8, $48, $2f, $00, $e8, $51, $2f, $00, $00
	db $55, $2f, $00, $00, $59, $2f, $00, $00, $5d, $2f, $00, $00, $61, $2f, $00, $00
	db $65, $2f, $00, $00, $69, $2f, $00, $00, $6d, $2f, $00, $00, $71, $2f, $00, $00
	db $75, $2f, $00, $00, $79, $2f, $f0, $f8, $84, $2f, $f0, $f8, $8f, $2f, $f0, $f0
	db $a3, $2f, $f0, $f0, $b8, $2f, $f8, $f8, $c1, $2f, $f8, $f8, $ca, $2f, $f8, $f8
	db $d1, $2f, $f8, $f8, $d8, $2f, $f0, $f8, $e3, $2f, $f0, $f8, $ee, $2f, $f0, $f0
	db $03, $30, $f0, $f0, $19, $30, $f8, $f8, $22, $30, $f8, $f8, $2b, $30, $f8, $f8
	db $32, $30, $f8, $f8, $39, $30, $f8, $f8, $40, $30, $f8, $f8, $47, $30, $f8, $f8
	db $4e, $30, $f8, $f8, $55, $30, $f8, $f8, $5c, $30, $f8, $f8, $67, $30, $f8, $f8
	db $6e, $30, $f8, $f8, $75, $30, $f8, $f8, $7c, $30, $f8, $f8, $83, $30, $f8, $f8
	db $8c, $30, $f8, $f8, $95, $30, $f8, $f8, $9e, $30, $f8, $f8, $a7, $30, $f8, $f8
	db $b0, $30, $f8, $f8, $b9, $30, $f8, $f8, $c0, $30, $f8, $f8, $46, $31, $f0, $f0
	db $5d, $31, $f8, $f8, $a9, $31, $fe, $fe, $fe, $fe, $fe, $fe, $fe, $fe, $84, $84
	db $84, $fe, $84, $ff, $a9, $31, $fe, $fe, $fe, $fe, $fe, $84, $fe, $fe, $fe, $84
	db $fe, $fe, $fe, $84, $84, $ff, $a9, $31, $fe, $fe, $fe, $fe, $fe, $fe, $84, $fe
	db $84, $84, $84, $fe, $ff, $a9, $31, $fe, $fe, $fe, $fe, $84, $84, $fe, $fe, $fe
	db $84, $fe, $fe, $fe, $84, $ff, $a9, $31, $fe, $fe, $fe, $fe, $fe, $fe, $fe, $fe
	db $81, $81, $81, $fe, $fe, $fe, $81, $ff, $a9, $31, $fe, $fe, $fe, $fe, $fe, $81
	db $81, $fe, $fe, $81, $fe, $fe, $fe, $81, $ff, $a9, $31, $fe, $fe, $fe, $fe, $81
	db $fe, $fe, $fe, $81, $81, $81, $ff, $a9, $31, $fe, $fe, $fe, $fe, $fe, $81, $fe
	db $fe, $fe, $81, $fe, $fe, $81, $81, $ff, $a9, $31, $fe, $fe, $fe, $fe, $fe, $fe
	db $fe, $fe, $8a, $8b, $8b, $8f, $ff, $a9, $31, $fe, $80, $fe, $fe, $fe, $88, $fe
	db $fe, $fe, $88, $fe, $fe, $fe, $89, $ff, $a9, $31, $fe, $fe, $fe, $fe, $fe, $fe
	db $fe, $fe, $8a, $8b, $8b, $8f, $ff, $a9, $31, $fe, $80, $fe, $fe, $fe, $88, $fe
	db $fe, $fe, $88, $fe, $fe, $fe, $89, $ff, $a9, $31, $fe, $fe, $fe, $fe, $fe, $fe
	db $fe, $fe, $fe, $83, $83, $fe, $fe, $83, $83, $ff, $a9, $31, $fe, $fe, $fe, $fe
	db $fe, $fe, $fe, $fe, $fe, $83, $83, $fe, $fe, $83, $83, $ff, $a9, $31, $fe, $fe
	db $fe, $fe, $fe, $fe, $fe, $fe, $fe, $83, $83, $fe, $fe, $83, $83, $ff, $a9, $31
	db $fe, $fe, $fe, $fe, $fe, $fe, $fe, $fe, $fe, $83, $83, $fe, $fe, $83, $83, $ff
	db $a9, $31, $fe, $fe, $fe, $fe, $fe, $fe, $fe, $fe, $82, $82, $fe, $fe, $fe, $82
	db $82, $ff, $a9, $31, $fe, $fe, $fe, $fe, $fe, $82, $fe, $fe, $82, $82, $fe, $fe
	db $82, $ff, $a9, $31, $fe, $fe, $fe, $fe, $fe, $fe, $fe, $fe, $82, $82, $fe, $fe
	db $fe, $82, $82, $ff, $a9, $31, $fe, $fe, $fe, $fe, $fe, $82, $fe, $fe, $82, $82
	db $fe, $fe, $82, $ff, $a9, $31, $fe, $fe, $fe, $fe, $fe, $fe, $fe, $fe, $fe, $86
	db $86, $fe, $86, $86, $ff, $a9, $31, $fe, $fe, $fe, $fe, $86, $fe, $fe, $fe, $86
	db $86, $fe, $fe, $fe, $86, $ff, $a9, $31, $fe, $fe, $fe, $fe, $fe, $fe, $fe, $fe
	db $fe, $86, $86, $fe, $86, $86, $ff, $a9, $31, $fe, $fe, $fe, $fe, $86, $fe, $fe
	db $fe, $86, $86, $fe, $fe, $fe, $86, $ff, $a9, $31, $fe, $fe, $fe, $fe, $fe, $85
	db $fe, $fe, $85, $85, $85, $ff, $a9, $31, $fe, $fe, $fe, $fe, $fe, $85, $fe, $fe
	db $85, $85, $fe, $fe, $fe, $85, $ff, $a9, $31, $fe, $fe, $fe, $fe, $fe, $fe, $fe
	db $fe, $85, $85, $85, $fe, $fe, $85, $ff, $a9, $31, $fe, $fe, $fe, $fe, $fe, $85
	db $fe, $fe, $fe, $85, $85, $fe, $fe, $85, $ff, $c9, $31, $0a, $25, $1d, $22, $19
	db $0e, $ff, $c9, $31, $0b, $25, $1d, $22, $19, $0e, $ff, $c9, $31, $0c, $25, $1d
	db $22, $19, $0e, $ff, $c9, $31, $2f, $18, $0f, $0f, $2f, $2f, $ff, $c9, $31, $00
	db $ff, $c9, $31, $01, $ff, $c9, $31, $02, $ff, $c9, $31, $03, $ff, $c9, $31, $04
	db $ff, $c9, $31, $05, $ff, $c9, $31, $06, $ff, $c9, $31, $07, $ff, $c9, $31, $08
	db $ff, $c9, $31, $09, $ff, $d9, $31, $2f, $01, $2f, $11, $20, $21, $30, $31, $ff
	db $d9, $31, $2f, $03, $12, $13, $22, $23, $32, $33, $ff, $a9, $31, $2f, $05, $fd
	db $05, $2f, $2f, $15, $04, $17, $24, $25, $26, $27, $34, $35, $36, $2f, $ff, $a9
	db $31, $08, $37, $fd, $37, $fd, $08, $18, $19, $14, $1b, $28, $29, $2a, $2b, $60
	db $70, $36, $2f, $ff, $d9, $31, $b9, $fd, $b9, $ba, $fd, $ba, $ff, $d9, $31, $82
	db $fd, $82, $83, $fd, $83, $ff, $d9, $31, $09, $0a, $3a, $3b, $ff, $d9, $31, $0b
	db $40, $7c, $6f, $ff, $d9, $31, $2f, $0f, $2f, $1f, $5f, $2c, $2f, $3f, $ff, $d9
	db $31, $6c, $3c, $4b, $4c, $5b, $5c, $6b, $2f, $ff, $a9, $31, $2f, $4d, $fd, $4d
	db $2f, $2f, $5d, $5e, $4e, $5f, $6d, $6e, $2f, $2f, $7d, $fd, $7d, $2f, $ff, $a9
	db $31, $08, $77, $fd, $77, $fd, $08, $18, $78, $43, $53, $7a, $7b, $50, $2f, $2f
	db $02, $fd, $7d, $2f, $ff, $d9, $31, $b9, $fd, $b9, $ba, $fd, $ba, $ff, $d9, $31
	db $82, $fd, $82, $83, $fd, $83, $ff, $d9, $31, $09, $0a, $3a, $3b, $ff, $d9, $31
	db $0b, $40, $7c, $6f, $ff, $d9, $31, $dc, $dd, $e0, $e1, $ff, $d9, $31, $de, $df
	db $e0, $e1, $ff, $d9, $31, $de, $e2, $e0, $e4, $ff, $d9, $31, $dc, $ee, $e0, $e3
	db $ff, $d9, $31, $e5, $e6, $e7, $e8, $ff, $d9, $31, $fd, $e6, $fd, $e5, $fd, $e8
	db $fd, $e7, $ff, $d9, $31, $e9, $ea, $eb, $ec, $ff, $d9, $31, $ed, $ea, $eb, $ec
	db $ff, $d9, $31, $f2, $f4, $f3, $bf, $ff, $d9, $31, $f4, $f2, $bf, $f3, $ff, $d9
	db $31, $c2, $fd, $c2, $c3, $fd, $c3, $ff, $d9, $31, $c4, $fd, $c4, $c5, $fd, $c5
	db $ff, $d9, $31, $dc, $fd, $dc, $ef, $fd, $ef, $ff, $d9, $31, $f0, $fd, $f0, $f1
	db $fd, $f1, $ff, $d9, $31, $dc, $fd, $f0, $f1, $fd, $ef, $ff, $d9, $31, $f0, $fd
	db $dc, $ef, $fd, $f1, $ff, $d9, $31, $bd, $be, $bb, $bc, $ff, $d9, $31, $b9, $ba
	db $da, $db, $ff, $cb, $30, $e0, $f0, $f5, $31, $c0, $c1, $c5, $c6, $cc, $cd, $75
	db $76, $a4, $a5, $a6, $a7, $54, $55, $56, $57, $44, $45, $46, $47, $a0, $a1, $a2
	db $a3, $9c, $9d, $9e, $9f, $ff, $16, $31, $f8, $e8, $1c, $31, $f0, $e8, $25, $31
	db $00, $00, $2b, $31, $00, $00, $31, $31, $00, $00, $3a, $31, $00, $00, $9d, $31
	db $00, $00, $a3, $31, $00, $00, $64, $31, $d8, $f8, $7c, $31, $e8, $f8, $8e, $31
	db $f0, $f8, $2d, $32, $63, $64, $65, $ff, $2d, $32, $63, $64, $65, $66, $67, $68
	db $ff, $2d, $32, $41, $41, $41, $ff, $2d, $32, $42, $42, $42, $ff, $2d, $32, $52
	db $52, $52, $62, $62, $62, $ff, $2d, $32, $51, $51, $51, $61, $61, $61, $71, $71
	db $71, $ff, $a9, $31, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $63, $64, $fd, $64
	db $fd, $63, $66, $67, $fd, $67, $fd, $66, $ff, $d9, $31, $2f, $2f, $63, $64, $ff
	db $d9, $31, $00, $fd, $00, $10, $fd, $10, $4f, $fd, $4f, $80, $fd, $80, $80, $fd
	db $80, $81, $fd, $81, $97, $fd, $97, $ff, $d9, $31, $98, $fd, $98, $99, $fd, $99
	db $80, $fd, $80, $9a, $fd, $9a, $9b, $fd, $9b, $ff, $d9, $31, $a8, $fd, $a8, $a9
	db $fd, $a9, $aa, $fd, $aa, $ab, $fd, $ab, $ff, $d9, $31, $41, $2f, $2f, $ff, $d9
	db $31, $52, $2f, $62, $ff, $00, $00, $00, $08, $00, $10, $00, $18, $08, $00, $08
	db $08, $08, $10, $08, $18, $10, $00, $10, $08, $10, $10, $10, $18, $18, $00, $18
	db $08, $18, $10, $18, $18, $00, $00, $00, $08, $00, $10, $00, $18, $00, $20, $00
	db $28, $00, $30, $00, $38, $00, $00, $00, $08, $08, $00, $08, $08, $10, $00, $10
	db $08, $18, $00, $18, $08, $20, $00, $20, $08, $28, $00, $28, $08, $30, $00, $30
	db $08, $00, $08, $00, $10, $08, $08, $08, $10, $10, $00, $10, $08, $10, $10, $10
	db $18, $18, $00, $18, $08, $18, $10, $18, $18, $20, $00, $20, $08, $20, $10, $20
	db $18, $28, $00, $28, $08, $28, $10, $28, $18, $30, $00, $30, $08, $30, $10, $30
	db $18, $38, $00, $38, $08, $38, $10, $38, $18, $00, $00, $00, $08, $00, $10, $08
	db $00, $08, $08, $08, $10, $10, $00, $10, $08, $10, $10

;@ asset: tiles bpp=2 length=$D00
;@ Tiles copied to $8300 by LoadGameTiles.
GameTiles::
	db $7f, $7f, $7f, $7f, $7f
	db $7f, $7f, $7f, $7f, $7f, $7c, $7c, $78, $79, $78, $7b, $ff, $ff, $ff, $ff, $ff
	db $ff, $ff, $ff, $ff, $ff, $00, $00, $00, $ff, $00, $00, $ff, $ff, $ff, $ff, $ff
	db $ff, $ff, $ff, $ff, $ff, $3f, $3f, $1f, $9f, $1f, $df, $78, $7b, $78, $79, $7c
	db $7c, $7f, $7f, $7f, $7f, $7f, $7f, $7f, $7f, $7f, $7f, $00, $00, $00, $ff, $00
	db $00, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $1f, $df, $1f, $9f, $3f
	db $3f, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $78, $7a, $78, $7a, $78
	db $7a, $78, $7a, $78, $7a, $78, $7a, $78, $7a, $78, $7a, $1f, $5f, $1f, $5f, $1f
	db $5f, $1f, $5f, $1f, $5f, $1f, $5f, $1f, $5f, $1f, $5f, $ff, $ff, $ff, $ff, $ff
	db $ff, $ff, $f8, $f8, $f0, $f2, $e1, $f5, $e3, $f2, $e6, $ff, $ff, $ff, $ff, $ff
	db $ff, $ff, $00, $00, $00, $00, $ff, $ff, $ff, $00, $00, $ff, $ff, $ff, $ff, $ff
	db $ff, $ff, $1f, $1f, $0f, $4f, $87, $af, $c7, $4f, $67, $f2, $e6, $f2, $e6, $f2
	db $e6, $f2, $e6, $f2, $e6, $f2, $e6, $f2, $e6, $f2, $e6, $4f, $67, $4f, $67, $4f
	db $67, $4f, $67, $4f, $67, $4f, $67, $4f, $67, $4f, $67, $f2, $e6, $f5, $e3, $f2
	db $e1, $f8, $f0, $ff, $f8, $ff, $ff, $ff, $ff, $ff, $ff, $00, $00, $ff, $ff, $00
	db $ff, $00, $00, $ff, $00, $ff, $ff, $ff, $ff, $ff, $ff, $4f, $67, $af, $c7, $4f
	db $87, $1f, $0f, $ff, $1f, $ff, $ff, $ff, $ff, $ff, $ff, $78, $7b, $78, $79, $7c
	db $7c, $7f, $7f, $7f, $7f, $7c, $7c, $78, $79, $78, $7b, $1f, $df, $1f, $9f, $3f
	db $3f, $ff, $ff, $ff, $ff, $3f, $3f, $1f, $9f, $1f, $df, $00, $00, $00, $ff, $00
	db $00, $ff, $ff, $ff, $ff, $00, $00, $00, $ff, $00, $00, $00, $00, $00, $7f, $00
	db $00, $7f, $7f, $7f, $7f, $7f, $7f, $7f, $7f, $7f, $7f, $78, $7a, $78, $7a, $78
	db $7a, $78, $7a, $78, $7a, $00, $02, $00, $7a, $00, $7a, $1f, $5f, $1f, $5f, $1f
	db $5f, $1f, $5f, $1f, $5f, $00, $40, $00, $5f, $00, $5f, $00, $00, $00, $ff, $00
	db $00, $00, $ff, $00, $ff, $00, $00, $00, $ff, $00, $00, $00, $00, $00, $00, $3f
	db $3f, $3f, $3f, $30, $30, $30, $30, $33, $32, $33, $30, $00, $00, $00, $00, $ff
	db $ff, $ff, $ff, $00, $00, $00, $00, $ff, $02, $ff, $20, $00, $00, $00, $00, $fc
	db $fc, $fc, $fc, $0c, $0c, $0c, $0c, $cc, $0c, $cc, $0c, $33, $30, $33, $30, $33
	db $30, $33, $30, $33, $30, $33, $30, $33, $32, $33, $30, $cc, $0c, $cc, $4c, $cc
	db $0c, $cc, $0c, $cc, $0c, $cc, $8c, $cc, $0c, $cc, $0c, $33, $30, $33, $30, $30
	db $30, $30, $30, $3f, $3f, $3f, $3f, $00, $00, $00, $00, $ff, $04, $ff, $40, $00
	db $00, $00, $00, $ff, $ff, $ff, $ff, $00, $00, $00, $00, $cc, $0c, $cc, $4c, $0c
	db $0c, $0c, $0c, $fc, $fc, $fc, $fc, $00, $00, $00, $00, $00, $00, $ff, $ff, $ff
	db $00, $ff, $02, $ff, $20, $ff, $00, $ff, $04, $ff, $00, $ff, $00, $ff, $02, $ff
	db $40, $ff, $00, $ff, $08, $ff, $01, $ff, $43, $ff, $07, $ff, $04, $ff, $40, $ff
	db $02, $ff, $00, $ff, $00, $ff, $ff, $ff, $ff, $00, $00, $ff, $00, $ff, $40, $ff
	db $02, $ff, $00, $ff, $10, $ff, $80, $ff, $c2, $ff, $e0, $fe, $06, $fe, $46, $fe
	db $06, $fe, $06, $fe, $16, $fe, $86, $fe, $06, $fe, $06, $7f, $64, $7f, $60, $7f
	db $62, $7f, $60, $7f, $60, $7f, $68, $7f, $62, $7f, $60, $ff, $02, $ff, $40, $ff
	db $00, $ff, $00, $ff, $08, $ff, $80, $ff, $1f, $f0, $10, $ff, $02, $ff, $20, $ff
	db $00, $ff, $00, $ff, $04, $ff, $00, $ff, $ff, $00, $00, $ff, $07, $ff, $13, $ff
	db $01, $ff, $00, $ff, $40, $ff, $00, $ff, $ff, $08, $08, $00, $00, $ff, $ff, $ff
	db $ff, $ff, $00, $ff, $02, $ff, $20, $ff, $ff, $00, $00, $ff, $e0, $ff, $c8, $ff
	db $80, $ff, $00, $ff, $02, $ff, $00, $ff, $ff, $08, $08, $ff, $00, $ff, $02, $ff
	db $40, $ff, $00, $ff, $02, $ff, $00, $ff, $f8, $0f, $08, $f0, $10, $f0, $10, $f0
	db $10, $f0, $50, $f0, $10, $f0, $10, $f0, $10, $f0, $10, $0f, $08, $0f, $0a, $0f
	db $08, $0f, $08, $0f, $08, $0f, $08, $0f, $09, $0f, $08, $00, $00, $00, $7f, $00
	db $00, $7f, $7f, $7f, $7f, $7c, $7c, $78, $79, $78, $7b, $00, $00, $00, $ff, $00
	db $00, $ff, $ff, $ff, $ff, $3f, $3f, $1f, $9f, $1f, $df, $7f, $7f, $7f, $7f, $7f
	db $7f, $7f, $7f, $7f, $7f, $00, $00, $00, $7f, $00, $00, $00, $00, $00, $00, $00
	db $00, $aa, $aa, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $0f
	db $0f, $1f, $1f, $38, $38, $33, $30, $36, $30, $34, $30, $00, $00, $00, $00, $ff
	db $ff, $ff, $ff, $00, $00, $ff, $00, $00, $00, $00, $00, $00, $00, $00, $00, $f0
	db $f0, $f8, $f8, $1c, $1c, $cc, $0c, $6c, $0c, $2c, $0c, $34, $30, $34, $30, $34
	db $30, $34, $30, $34, $30, $34, $30, $34, $30, $34, $30, $2c, $0c, $2c, $0c, $2c
	db $0c, $2c, $0c, $2c, $0c, $2c, $0c, $2c, $0c, $2c, $0c, $34, $30, $36, $30, $33
	db $30, $38, $38, $1f, $1f, $0f, $0f, $00, $00, $00, $00, $00, $7b, $00, $79, $00
	db $7c, $00, $7f, $00, $7f, $00, $00, $00, $7f, $00, $00, $00, $df, $00, $9f, $00
	db $3f, $00, $ff, $00, $ff, $00, $00, $00, $ff, $00, $00, $00, $00, $00, $00, $ff
	db $00, $00, $00, $ff, $ff, $ff, $ff, $00, $00, $00, $00, $2c, $0c, $6c, $0c, $cc
	db $0c, $1c, $1c, $f8, $f8, $f0, $f0, $00, $00, $00, $00, $08, $08, $ff, $ff, $ff
	db $02, $ff, $00, $ff, $20, $ff, $00, $ff, $02, $ff, $00, $00, $00, $ff, $ff, $ff
	db $ff, $ff, $00, $ff, $02, $ff, $20, $ff, $ff, $08, $08, $ff, $07, $ff, $13, $ff
	db $01, $ff, $00, $ff, $40, $ff, $00, $ff, $ff, $00, $00, $ff, $e0, $ff, $c8, $ff
	db $80, $ff, $00, $ff, $02, $ff, $00, $ff, $ff, $00, $00, $08, $08, $08, $08, $08
	db $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $08, $ff, $00, $ff, $02, $ff
	db $00, $ff, $20, $ff, $02, $ff, $00, $ff, $ff, $08, $08, $f0, $10, $ff, $1f, $f0
	db $1f, $f0, $1f, $f0, $1f, $f0, $1f, $ff, $5f, $f0, $10, $00, $00, $ff, $ff, $00
	db $ff, $00, $ff, $00, $ff, $00, $ff, $ff, $ff, $00, $00, $08, $08, $ff, $ff, $00
	db $ff, $00, $ff, $00, $ff, $00, $ff, $ff, $ff, $08, $08, $0f, $08, $ff, $f8, $0f
	db $f8, $0f, $f8, $0f, $f8, $0f, $f8, $ff, $fa, $0f, $08, $ff, $07, $ff, $43, $ff
	db $01, $ff, $00, $ff, $00, $ff, $80, $ff, $1f, $f0, $10, $ff, $e0, $ff, $c2, $ff
	db $80, $ff, $00, $ff, $22, $ff, $00, $ff, $f8, $0f, $08, $00, $00, $00, $00, $00
	db $00, $3c, $00, $3c, $00, $00, $00, $00, $00, $00, $00, $00, $00, $3c, $00, $4e
	db $00, $4e, $00, $7e, $00, $4e, $00, $4e, $00, $00, $00, $00, $00, $7c, $00, $66
	db $00, $7c, $00, $66, $00, $66, $00, $7c, $00, $00, $00, $00, $00, $3c, $00, $66
	db $00, $60, $00, $60, $00, $66, $00, $3c, $00, $00, $00, $dd, $44, $ff, $44, $ff
	db $ff, $77, $11, $ff, $11, $ff, $ff, $dd, $44, $ff, $44, $ff, $ff, $77, $11, $ff
	db $11, $ff, $ff, $dd, $44, $ff, $44, $ff, $ff, $77, $11, $ff, $11, $ff, $ff, $dd
	db $44, $ff, $44, $ff, $ff, $77, $11, $ff, $11, $ff, $ff, $00, $00, $7e, $00, $18
	db $00, $18, $00, $18, $00, $18, $00, $18, $00, $00, $00, $00, $00, $66, $00, $66
	db $00, $3c, $00, $18, $00, $18, $00, $18, $00, $00, $00, $ff, $ff, $f7, $89, $dd
	db $a3, $ff, $81, $b7, $c9, $fd, $83, $d7, $a9, $ff, $81, $ff, $ff, $ff, $81, $ff
	db $bd, $e7, $a5, $e7, $a5, $ff, $bd, $ff, $81, $ff, $ff, $ff, $ff, $ff, $81, $ff
	db $81, $ff, $99, $ff, $99, $ff, $81, $ff, $81, $ff, $ff, $ff, $ff, $81, $81, $bd
	db $bd, $bd, $bd, $bd, $bd, $bd, $bd, $81, $81, $ff, $ff, $ff, $ff, $81, $ff, $81
	db $ff, $81, $ff, $81, $ff, $81, $ff, $81, $ff, $ff, $ff, $ff, $ff, $ff, $81, $c3
	db $81, $df, $85, $df, $85, $ff, $bd, $ff, $81, $ff, $ff, $ff, $ff, $81, $ff, $bd
	db $ff, $a5, $e7, $a5, $e7, $bd, $ff, $81, $ff, $ff, $ff, $ff, $ff, $81, $81, $bd
	db $83, $bd, $83, $bd, $83, $bd, $83, $81, $ff, $ff, $ff, $ed, $93, $bf, $c1, $f5
	db $8b, $df, $a1, $fd, $83, $af, $d1, $fb, $85, $df, $a1, $fd, $83, $ef, $91, $bb
	db $c5, $ef, $91, $bd, $c3, $f7, $89, $df, $a1, $ff, $ff, $ff, $ff, $db, $a4, $ff
	db $80, $b5, $ca, $ff, $80, $dd, $a2, $f7, $88, $ff, $ff, $ff, $ff, $57, $a8, $fd
	db $02, $df, $20, $7b, $84, $ee, $11, $bb, $44, $ff, $ff, $ff, $00, $ff, $00, $ff
	db $00, $ff, $00, $ff, $00, $ff, $00, $ff, $00, $ff, $00, $00, $ff, $00, $ff, $00
	db $ff, $00, $ff, $00, $ff, $00, $ff, $00, $ff, $00, $ff, $ff, $ff, $ff, $ff, $ff
	db $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $77, $89, $df
	db $21, $fb, $05, $af, $51, $fd, $03, $d7, $29, $ff, $ff, $00, $00, $3c, $00, $66
	db $00, $66, $00, $66, $00, $66, $00, $3c, $00, $00, $00, $00, $00, $18, $00, $38
	db $00, $18, $00, $18, $00, $18, $00, $3c, $00, $00, $00, $00, $00, $3c, $00, $4e
	db $00, $0e, $00, $3c, $00, $70, $00, $7e, $00, $00, $00, $00, $00, $7c, $00, $0e
	db $00, $3c, $00, $0e, $00, $0e, $00, $7c, $00, $00, $00, $00, $00, $3c, $00, $6c
	db $00, $4c, $00, $4e, $00, $7e, $00, $0c, $00, $00, $00, $00, $00, $7c, $00, $60
	db $00, $7c, $00, $0e, $00, $4e, $00, $3c, $00, $00, $00, $00, $00, $3c, $00, $60
	db $00, $7c, $00, $66, $00, $66, $00, $3c, $00, $00, $00, $00, $00, $7e, $00, $06
	db $00, $0c, $00, $18, $00, $38, $00, $38, $00, $00, $00, $00, $00, $3c, $00, $4e
	db $00, $3c, $00, $4e, $00, $4e, $00, $3c, $00, $00, $00, $00, $00, $3c, $00, $4e
	db $00, $4e, $00, $3e, $00, $0e, $00, $3c, $00, $00, $00, $00, $00, $7c, $00, $66
	db $00, $66, $00, $7c, $00, $60, $00, $60, $00, $00, $00, $00, $00, $7e, $00, $60
	db $00, $7c, $00, $60, $00, $60, $00, $7e, $00, $00, $00, $00, $00, $7e, $00, $60
	db $00, $60, $00, $7c, $00, $60, $00, $60, $00, $00, $00, $00, $00, $3c, $00, $66
	db $00, $66, $00, $66, $00, $66, $00, $3c, $00, $00, $00, $00, $00, $3c, $00, $66
	db $00, $60, $00, $6e, $00, $66, $00, $3e, $00, $00, $00, $00, $00, $46, $00, $6e
	db $00, $7e, $00, $56, $00, $46, $00, $46, $00, $00, $00, $00, $00, $46, $00, $46
	db $00, $46, $00, $46, $00, $4e, $00, $3c, $00, $00, $00, $00, $00, $3c, $00, $60
	db $00, $3c, $00, $0e, $00, $4e, $00, $3c, $00, $00, $00, $00, $00, $3c, $00, $18
	db $00, $18, $00, $18, $00, $18, $00, $3c, $00, $00, $00, $00, $00, $60, $00, $60
	db $00, $60, $00, $60, $00, $60, $00, $7e, $00, $00, $00, $00, $00, $46, $00, $46
	db $00, $46, $00, $46, $00, $2c, $00, $18, $00, $00, $00, $00, $00, $7c, $00, $66
	db $00, $66, $00, $7c, $00, $68, $00, $66, $00, $00, $00, $00, $00, $46, $00, $66
	db $00, $76, $00, $5e, $00, $4e, $00, $46, $00, $00, $00, $00, $00, $7c, $00, $4e
	db $00, $4e, $00, $4e, $00, $4e, $00, $7c, $00, $00, $00, $ff, $ff, $ff, $00, $ff
	db $00, $ff, $00, $ff, $10, $ff, $80, $ff, $02, $ff, $00, $00, $00, $ff, $ff, $ff
	db $ff, $ff, $00, $ff, $02, $ff, $20, $ff, $ff, $80, $80, $80, $80, $80, $80, $80
	db $80, $80, $80, $80, $80, $80, $80, $80, $80, $80, $80, $80, $80, $ff, $ff, $00
	db $ff, $00, $ff, $00, $ff, $00, $ff, $ff, $ff, $80, $80, $80, $80, $ff, $ff, $ff
	db $00, $ff, $02, $ff, $20, $ff, $00, $ff, $00, $ff, $00, $ff, $00, $00, $00, $00
	db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $07, $07, $18, $1f, $21
	db $3e, $47, $7f, $5f, $7f, $39, $30, $7b, $62, $fb, $b2, $ff, $a0, $ff, $c2, $7f
	db $54, $7f, $5c, $3f, $2e, $7f, $63, $bf, $f8, $37, $ff, $01, $01, $01, $01, $01
	db $01, $01, $01, $01, $01, $01, $01, $01, $01, $83, $83, $01, $01, $01, $01, $01
	db $01, $01, $01, $01, $01, $01, $01, $01, $01, $ff, $ff, $ff, $ff, $01, $01, $01
	db $01, $01, $01, $01, $01, $01, $01, $01, $01, $83, $83, $ff, $ff, $d9, $87, $d9
	db $87, $d9, $87, $d9, $87, $d9, $87, $d9, $87, $d9, $87, $d9, $87, $d9, $87, $d9
	db $87, $d9, $87, $d9, $87, $d9, $87, $d9, $87, $ff, $ff, $d9, $87, $d9, $87, $d9
	db $87, $d9, $87, $d9, $87, $d9, $87, $d9, $87, $d9, $87, $00, $38, $00, $38, $00
	db $38, $00, $38, $00, $38, $00, $38, $00, $38, $00, $38, $7c, $00, $7c, $00, $7c
	db $00, $7c, $00, $7c, $00, $7c, $00, $7f, $00, $ff, $00, $00, $00, $00, $00, $08
	db $00, $08, $00, $08, $00, $08, $00, $1c, $00, $1c, $00, $00, $00, $00, $0e, $01
	db $1d, $1e, $06, $2a, $2a, $27, $27, $10, $13, $0c, $0d, $00, $00, $c0, $c0, $20
	db $20, $10, $d0, $d0, $10, $f0, $30, $c8, $e8, $08, $e8, $04, $07, $03, $03, $0c
	db $0c, $10, $10, $35, $20, $2a, $20, $3f, $3f, $0c, $0c, $28, $e8, $d8, $c0, $40
	db $40, $20, $20, $50, $10, $b0, $10, $f0, $f0, $c0, $c0, $00, $e0, $01, $71, $32
	db $42, $34, $35, $55, $54, $4f, $4e, $21, $27, $18, $1b, $00, $00, $80, $80, $40
	db $40, $20, $a0, $a0, $20, $e0, $60, $90, $f0, $08, $c8, $b8, $b8, $84, $84, $84
	db $84, $fc, $fc, $92, $92, $92, $92, $6c, $6c, $ee, $ee, $07, $07, $1f, $18, $3e
	db $20, $7f, $4f, $7f, $5f, $70, $70, $a2, $a2, $b0, $b0, $b4, $b4, $64, $64, $3c
	db $3c, $2e, $2e, $27, $27, $10, $10, $6c, $7c, $cf, $b3, $03, $03, $03, $03, $03
	db $02, $07, $06, $09, $09, $16, $17, $12, $11, $0e, $0f, $08, $09, $08, $08, $0f
	db $0f, $08, $08, $09, $09, $0a, $0a, $06, $06, $0e, $0e, $03, $03, $03, $03, $03
	db $02, $1f, $1e, $21, $21, $4a, $55, $4a, $75, $0a, $35, $0a, $15, $08, $08, $0f
	db $0f, $08, $08, $09, $09, $0a, $0a, $06, $06, $0e, $0e, $00, $00, $66, $00, $6c
	db $00, $78, $00, $78, $00, $6c, $00, $66, $00, $00, $00, $00, $00, $46, $00, $2c
	db $00, $18, $00, $38, $00, $64, $00, $42, $00, $00, $00, $fd, $fd, $fd, $fd, $fd
	db $fd, $fd, $fd, $fd, $fd, $fd, $fd, $fd, $fd, $fd, $fd, $f8, $00, $e0, $00, $c0
	db $00, $80, $00, $80, $00, $00, $00, $00, $00, $00, $00, $7f, $00, $1f, $00, $0f
	db $00, $07, $00, $07, $00, $03, $00, $03, $00, $03, $00, $00, $00, $80, $00, $80
	db $00, $c0, $00, $e0, $00, $f8, $00, $ff, $00, $ff, $00, $03, $00, $07, $00, $07
	db $00, $0f, $00, $1f, $00, $7f, $00, $ff, $00, $ff, $00, $ff, $ff, $ff, $ff, $00
	db $ff, $ff, $ff, $00, $ff, $ff, $00, $00, $ff, $ff, $00, $ff, $00, $ff, $00, $ff
	db $01, $fe, $02, $fe, $02, $fc, $04, $fc, $04, $fc, $04, $ff, $02, $ff, $01, $ff
	db $01, $01, $01, $ff, $01, $01, $01, $ff, $01, $01, $01, $02, $02, $02, $02, $03
	db $03, $04, $05, $08, $09, $11, $12, $21, $26, $43, $4c, $00, $00, $01, $01, $02
	db $02, $04, $04, $08, $09, $10, $13, $20, $27, $20, $2f, $87, $98, $06, $39, $0e
	db $71, $1e, $e1, $3c, $c3, $3c, $c3, $78, $87, $78, $87, $40, $4f, $40, $4f, $80
	db $9f, $80, $9f, $80, $9f, $80, $9f, $80, $9f, $80, $9f, $f8, $07, $f0, $0f, $f0
	db $0f, $f0, $0f, $f0, $0f, $f0, $0f, $f0, $0f, $f8, $07, $40, $5f, $40, $4f, $20
	db $2f, $20, $27, $10, $11, $0f, $0f, $04, $04, $07, $07, $78, $87, $7c, $83, $3c
	db $c3, $1e, $e1, $0f, $f0, $ff, $ff, $ff, $00, $ff, $ff, $ff, $00, $ff, $00, $ff
	db $00, $00, $00, $ff, $00, $00, $00, $ff, $00, $00, $00, $02, $00, $02, $00, $02
	db $00, $02, $00, $02, $00, $02, $00, $02, $00, $02, $00, $10, $00, $38, $00, $7c
	db $00, $fe, $00, $fe, $00, $fe, $00, $7c, $00, $00, $00, $02, $03, $01, $01, $02
	db $02, $04, $04, $0d, $08, $0a, $08, $0f, $0f, $03, $03, $28, $e8, $f0, $d0, $30
	db $30, $08, $08, $54, $04, $ac, $04, $fc, $fc, $30, $30, $00, $00, $03, $03, $03
	db $03, $03, $02, $07, $06, $09, $09, $08, $08, $0b, $0b, $00, $00, $c0, $c0, $c4
	db $c4, $e8, $68, $90, $f0, $a8, $f8, $48, $78, $f8, $b8, $00, $00, $07, $07, $07
	db $07, $07, $04, $07, $04, $0b, $0b, $10, $10, $17, $17, $00, $00, $80, $80, $80
	db $80, $e0, $e0, $90, $f0, $a8, $f8, $48, $78, $b8, $b8, $08, $08, $0f, $0f, $08
	db $08, $0f, $0f, $09, $09, $09, $09, $06, $06, $0e, $0e, $e4, $e4, $22, $22, $20
	db $20, $e0, $e0, $20, $20, $20, $20, $c0, $c0, $e0, $e0, $18, $18, $98, $98, $98
	db $98, $f8, $f8, $9c, $98, $3c, $3c, $3c, $3c, $7e, $7e, $7f, $00, $fe, $fe, $7e
	db $7e, $fe, $da, $7e, $5a, $7e, $7e, $fc, $fc, $f8, $f8, $fe, $0e, $fe, $fe, $7e
	db $7e, $fe, $da, $7e, $5a, $7e, $7e, $fc, $fc, $f8, $f8, $80, $80, $83, $83, $83
	db $83, $c3, $02, $ef, $2e, $97, $97, $47, $44, $24, $24, $00, $00, $c0, $c0, $c0
	db $c0, $c0, $40, $e0, $60, $f8, $f8, $e4, $24, $34, $34, $17, $14, $17, $14, $17
	db $14, $1c, $1f, $17, $17, $0f, $0f, $1e, $1e, $00, $00, $f4, $24, $f8, $28, $e8
	db $28, $38, $f8, $e8, $e8, $90, $90, $70, $70, $78, $78, $03, $03, $03, $03, $03
	db $02, $0f, $0e, $11, $11, $37, $37, $71, $52, $7d, $4e, $c0, $c0, $c0, $c0, $c0
	db $40, $c0, $40, $a0, $a0, $10, $10, $ff, $ff, $cf, $33, $7f, $40, $3f, $3f, $08
	db $08, $0f, $0f, $09, $09, $09, $09, $06, $06, $0e, $0e, $fc, $fc, $20, $20, $20
	db $20, $e0, $e0, $20, $20, $20, $20, $c0, $c0, $e0, $e0, $03, $03, $03, $03, $03
	db $02, $07, $06, $09, $09, $33, $33, $77, $54, $73, $4c, $18, $18, $d8, $d8, $d8
	db $d8, $f8, $78, $dc, $58, $bc, $bc, $3c, $3c, $7e, $7e, $09, $0e, $07, $07, $08
	db $0f, $08, $0f, $09, $0f, $0a, $0e, $06, $06, $0e, $0e, $00, $00, $03, $03, $03
	db $03, $03, $02, $ff, $7e, $c9, $3f, $78, $7f, $09, $0f, $04, $04, $07, $07, $b8
	db $bf, $c0, $ff, $ff, $ff, $00, $00, $00, $00, $00, $00, $00, $00, $78, $78, $78
	db $78, $7b, $48, $60, $5f, $b6, $b0, $84, $84, $b8, $b8, $84, $84, $84, $84, $84
	db $84, $fa, $fa, $92, $92, $9e, $9e, $67, $67, $e0, $e0, $00, $00, $00, $00, $78
	db $78, $78, $78, $78, $48, $40, $7e, $b4, $b0, $84, $84

;@ asset: tilemap width=20 height=18 tiles=LoadGameTiles
;@ The type A game screen (State0A_StartGame).
GameScreenTypeA::
	db $2a, $7b, $2f, $2f, $2f
	db $2f, $2f, $2f, $2f, $2f, $2f, $2f, $7b, $30, $31, $31, $31, $31, $31, $32, $2a
	db $7c, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $7c, $44, $1c, $0c, $18
	db $1b, $0e, $45, $2a, $7d, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $7d
	db $67, $46, $46, $46, $46, $46, $68, $2a, $7b, $2f, $2f, $2f, $2f, $2f, $2f, $2f
	db $2f, $2f, $2f, $7b, $2f, $2f, $2f, $2f, $2f, $00, $2f, $2a, $7c, $2f, $2f, $2f
	db $2f, $2f, $2f, $2f, $2f, $2f, $2f, $7c, $43, $34, $34, $34, $34, $34, $34, $2a
	db $7d, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $7d, $30, $31, $31, $31
	db $31, $31, $32, $2a, $7b, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $7b
	db $36, $15, $0e, $1f, $0e, $15, $37, $2a, $7c, $2f, $2f, $2f, $2f, $2f, $2f, $2f
	db $2f, $2f, $2f, $7c, $36, $2f, $2f, $2f, $2f, $2f, $37, $2a, $7d, $2f, $2f, $2f
	db $2f, $2f, $2f, $2f, $2f, $2f, $2f, $7d, $40, $42, $42, $42, $42, $42, $41, $2a
	db $7b, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $7b, $36, $15, $12, $17
	db $0e, $1c, $37, $2a, $7c, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $7c
	db $36, $2f, $2f, $2f, $2f, $2f, $37, $2a, $7d, $2f, $2f, $2f, $2f, $2f, $2f, $2f
	db $2f, $2f, $2f, $7d, $33, $34, $34, $34, $34, $34, $35, $2a, $7b, $2f, $2f, $2f
	db $2f, $2f, $2f, $2f, $2f, $2f, $2f, $7b, $2b, $38, $39, $39, $39, $39, $3a, $2a
	db $7c, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $7c, $2b, $3b, $2f, $2f
	db $2f, $2f, $3c, $2a, $7d, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $7d
	db $2b, $3b, $2f, $2f, $2f, $2f, $3c, $2a, $7b, $2f, $2f, $2f, $2f, $2f, $2f, $2f
	db $2f, $2f, $2f, $7b, $2b, $3b, $2f, $2f, $2f, $2f, $3c, $2a, $7c, $2f, $2f, $2f
	db $2f, $2f, $2f, $2f, $2f, $2f, $2f, $7c, $2b, $3b, $2f, $2f, $2f, $2f, $3c, $2a
	db $7d, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $7d, $2b, $3d, $3e, $3e
	db $3e, $3e, $3f

;@ asset: tilemap width=20 height=18 tiles=LoadGameTiles
;@ The type B game screen (State0A_StartGame).
GameScreenTypeB::
	db $2a, $7b, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $7b
	db $30, $31, $31, $31, $31, $31, $32, $2a, $7c, $2f, $2f, $2f, $2f, $2f, $2f, $2f
	db $2f, $2f, $2f, $7c, $36, $15, $0e, $1f, $0e, $15, $37, $2a, $7d, $2f, $2f, $2f
	db $2f, $2f, $2f, $2f, $2f, $2f, $2f, $7d, $36, $2f, $2f, $2f, $2f, $2f, $37, $2a
	db $7b, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $7b, $40, $42, $42, $42
	db $42, $42, $41, $2a, $7c, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $7c
	db $36, $11, $12, $10, $11, $2f, $37, $2a, $7d, $2f, $2f, $2f, $2f, $2f, $2f, $2f
	db $2f, $2f, $2f, $7d, $36, $2f, $2f, $2f, $2f, $2f, $37, $2a, $7b, $2f, $2f, $2f
	db $2f, $2f, $2f, $2f, $2f, $2f, $2f, $7b, $33, $34, $34, $34, $34, $34, $35, $2a
	db $7c, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $7c, $2b, $8e, $8e, $8e
	db $8e, $8e, $8e, $2a, $7d, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $7d
	db $30, $31, $31, $31, $31, $31, $32, $2a, $7b, $2f, $2f, $2f, $2f, $2f, $2f, $2f
	db $2f, $2f, $2f, $7b, $36, $15, $12, $17, $0e, $1c, $37, $2a, $7c, $2f, $2f, $2f
	db $2f, $2f, $2f, $2f, $2f, $2f, $2f, $7c, $36, $2f, $2f, $02, $05, $2f, $37, $2a
	db $7d, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $7d, $33, $34, $34, $34
	db $34, $34, $35, $2a, $7b, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $7b
	db $2b, $38, $39, $39, $39, $39, $3a, $2a, $7c, $2f, $2f, $2f, $2f, $2f, $2f, $2f
	db $2f, $2f, $2f, $7c, $2b, $3b, $2f, $2f, $2f, $2f, $3c, $2a, $7d, $2f, $2f, $2f
	db $2f, $2f, $2f, $2f, $2f, $2f, $2f, $7d, $2b, $3b, $2f, $2f, $2f, $2f, $3c, $2a
	db $7b, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $7b, $2b, $3b, $2f, $2f
	db $2f, $2f, $3c, $2a, $7c, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $7c
	db $2b, $3b, $2f, $2f, $2f, $2f, $3c, $2a, $7d, $2f, $2f, $2f, $2f, $2f, $2f, $2f
	db $2f, $2f, $2f, $7d, $2b, $3d, $3e, $3e, $3e, $3e, $3f

;@ asset: tiles bpp=1 length=$138
;@ Font: 39 tiles of 1bpp pixel data, expanded into VRAM by LoadFont.
Font1bpp::
	db $00, $3c, $66, $66, $66
	db $66, $3c, $00, $00, $18, $38, $18, $18, $18, $3c, $00, $00, $3c, $4e, $0e, $3c
	db $70, $7e, $00, $00, $7c, $0e, $3c, $0e, $0e, $7c, $00, $00, $3c, $6c, $4c, $4e
	db $7e, $0c, $00, $00, $7c, $60, $7c, $0e, $4e, $3c, $00, $00, $3c, $60, $7c, $66
	db $66, $3c, $00, $00, $7e, $06, $0c, $18, $38, $38, $00, $00, $3c, $4e, $3c, $4e
	db $4e, $3c, $00, $00, $3c, $4e, $4e, $3e, $0e, $3c, $00, $00, $3c, $4e, $4e, $7e
	db $4e, $4e, $00, $00, $7c, $66, $7c, $66, $66, $7c, $00, $00, $3c, $66, $60, $60
	db $66, $3c, $00, $00, $7c, $4e, $4e, $4e, $4e, $7c, $00, $00, $7e, $60, $7c, $60
	db $60, $7e, $00, $00, $7e, $60, $60, $7c, $60, $60, $00, $00, $3c, $66, $60, $6e
	db $66, $3e, $00, $00, $46, $46, $7e, $46, $46, $46, $00, $00, $3c, $18, $18, $18
	db $18, $3c, $00, $00, $1e, $0c, $0c, $6c, $6c, $38, $00, $00, $66, $6c, $78, $78
	db $6c, $66, $00, $00, $60, $60, $60, $60, $60, $7e, $00, $00, $46, $6e, $7e, $56
	db $46, $46, $00, $00, $46, $66, $76, $5e, $4e, $46, $00, $00, $3c, $66, $66, $66
	db $66, $3c, $00, $00, $7c, $66, $66, $7c, $60, $60, $00, $00, $3c, $62, $62, $6a
	db $64, $3a, $00, $00, $7c, $66, $66, $7c, $68, $66, $00, $00, $3c, $60, $3c, $0e
	db $4e, $3c, $00, $00, $7e, $18, $18, $18, $18, $18, $00, $00, $46, $46, $46, $46
	db $4e, $3c, $00, $00, $46, $46, $46, $46, $2c, $18, $00, $00, $46, $46, $56, $7e
	db $6e, $46, $00, $00, $46, $2c, $18, $38, $64, $42, $00, $00, $66, $66, $3c, $18
	db $18, $18, $00, $00, $7e, $0e, $1c, $38, $70, $7e, $00, $00, $00, $00, $00, $00
	db $60, $60, $00, $00, $00, $00, $3c, $3c, $00, $00, $00, $00, $00, $22, $14, $08
	db $14, $22, $00

;@ asset: tiles bpp=2 length=$DA0
;@ Tiles copied right after the font (to $8270) by LoadTitleTiles (all of them)
;@ and LoadGameTiles (only the first $A0 bytes).
TitleTiles::
	db $00, $00, $36, $36, $5f, $49, $5f, $41, $7f, $41, $3e, $22, $1c
	db $14, $08, $08, $ff, $ff, $ff, $81, $c1, $bf, $c1, $bf, $c1, $bf, $c1, $bf, $81
	db $ff, $ff, $ff, $aa, $aa, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
	db $00, $00, $00, $fe, $fe, $fe, $fe, $fe, $fe, $fe, $fe, $fe, $fe, $fe, $fe, $fe
	db $fe, $fe, $fe, $7f, $7f, $7f, $7f, $7f, $7f, $7f, $7f, $7f, $7f, $7f, $7f, $7f
	db $7f, $7f, $7f, $ff, $00, $ff, $40, $ff, $02, $ff, $00, $ff, $10, $ff, $80, $ff
	db $02, $ff, $00, $f0, $10, $ff, $1f, $ff, $00, $ff, $40, $ff, $00, $ff, $02, $ff
	db $40, $ff, $00, $0f, $08, $ff, $f8, $ff, $00, $ff, $02, $ff, $00, $ff, $40, $ff
	db $02, $ff, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
	db $00, $00, $00, $00, $00, $00, $00, $18, $18, $38, $38, $18, $18, $18, $18, $18
	db $18, $3c, $3c, $00, $00, $00, $00, $3c, $3c, $4e, $4e, $4e, $4e, $3e, $3e, $0e
	db $0e, $3c, $3c, $00, $00, $00, $00, $3c, $3c, $4e, $4e, $3c, $3c, $4e, $4e, $4e
	db $4e, $3c, $3c, $00, $00, $38, $38, $44, $44, $ba, $ba, $a2, $a2, $ba, $ba, $44
	db $44, $38, $38, $c6, $c6, $e6, $e6, $e6, $e6, $d6, $d6, $d6, $d6, $ce, $ce, $ce
	db $ce, $c6, $c6, $c0, $c0, $c0, $c0, $00, $00, $db, $db, $dd, $dd, $d9, $d9, $d9
	db $d9, $d9, $d9, $00, $00, $30, $30, $78, $78, $33, $33, $b6, $b6, $b7, $b7, $b6
	db $b6, $b3, $b3, $00, $00, $00, $00, $00, $00, $cd, $cd, $6e, $6e, $ec, $ec, $0c
	db $0c, $ec, $ec, $01, $01, $01, $01, $01, $01, $8f, $8f, $d9, $d9, $d9, $d9, $d9
	db $d9, $cf, $cf, $80, $80, $80, $80, $80, $80, $9e, $9e, $b3, $b3, $b3, $b3, $b3
	db $b3, $9e, $9e, $ff, $00, $ff, $00, $ff, $00, $ef, $00, $ff, $00, $ff, $00, $ff
	db $00, $ff, $00, $ff, $00, $ff, $00, $ff, $00, $e7, $00, $e7, $00, $ff, $00, $ff
	db $00, $ff, $00, $00, $ff, $ff, $ff, $00, $ff, $00, $ff, $ff, $00, $00, $ff, $ff
	db $00, $ff, $00, $00, $ff, $ff, $ff, $01, $ff, $02, $fe, $fe, $02, $04, $fc, $fc
	db $04, $fc, $04, $00, $ff, $ff, $ff, $80, $ff, $40, $7f, $ff, $40, $e0, $3f, $ff
	db $20, $bf, $60, $ff, $00, $ff, $00, $ff, $01, $fe, $02, $fe, $02, $fc, $04, $fc
	db $04, $fc, $04, $ff, $00, $ff, $00, $ff, $80, $7f, $40, $ff, $40, $ff, $20, $ff
	db $20, $bf, $60, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $00
	db $00, $00, $00, $ff, $02, $ff, $01, $ff, $01, $ff, $01, $ff, $01, $ff, $01, $ff
	db $01, $ff, $01, $7f, $c0, $ff, $80, $ff, $80, $ff, $80, $ff, $80, $ff, $80, $ff
	db $80, $ff, $80, $fe, $02, $fe, $02, $ff, $03, $fc, $05, $f8, $09, $f1, $12, $e1
	db $26, $c3, $4c, $7f, $c0, $7f, $c0, $ff, $c0, $bf, $60, $9f, $70, $af, $58, $27
	db $dc, $33, $ce, $ff, $00, $ff, $01, $fe, $02, $fc, $04, $f8, $09, $f0, $13, $e0
	db $27, $e0, $2f, $87, $98, $06, $39, $0e, $71, $1e, $e1, $3c, $c3, $3c, $c3, $78
	db $87, $78, $87, $35, $cb, $32, $cd, $3a, $c5, $79, $86, $78, $87, $78, $87, $7c
	db $83, $7c, $83, $ff, $00, $ff, $80, $7f, $c0, $3f, $e0, $9f, $70, $4f, $b8, $67
	db $9c, $37, $cc, $c0, $4f, $c0, $4f, $80, $9f, $80, $9f, $80, $9f, $80, $9f, $80
	db $9f, $80, $9f, $f8, $07, $f0, $0f, $f0, $0f, $f0, $0f, $f0, $0f, $f0, $0f, $f0
	db $0f, $f8, $07, $7c, $83, $7e, $81, $7e, $81, $3e, $c1, $3f, $c0, $1f, $e0, $1f
	db $e0, $1f, $e0, $33, $ce, $1b, $e6, $09, $f7, $0d, $f3, $0d, $f3, $0d, $f3, $0d
	db $f3, $09, $f7, $c0, $5f, $c0, $4f, $e0, $2f, $e0, $27, $f0, $11, $bf, $4f, $0c
	db $f4, $07, $ff, $78, $87, $7c, $83, $3c, $c3, $1e, $e1, $0f, $f0, $ff, $ff, $ff
	db $00, $ff, $ff, $0f, $f0, $0f, $f0, $0e, $f1, $0e, $f1, $06, $f9, $ff, $ff, $c5
	db $3f, $ff, $ff, $1b, $e6, $13, $ee, $37, $cc, $27, $dc, $4f, $b8, $fc, $f3, $fc
	db $a3, $e0, $ff, $fe, $02, $fe, $02, $bf, $43, $1c, $e5, $b8, $49, $b1, $52, $a1
	db $66, $43, $cc, $ff, $00, $ff, $00, $ff, $00, $ff, $00, $ff, $00, $ff, $00, $ef
	db $10, $c7, $38, $ff, $00, $fb, $04, $fb, $04, $fb, $04, $fb, $04, $f1, $0e, $f1
	db $0e, $f1, $0e, $83, $7c, $01, $fe, $01, $fe, $01, $fe, $83, $7c, $ff, $00, $83
	db $7c, $83, $7c, $f1, $0e, $e0, $1f, $e0, $1f, $e0, $1f, $e0, $1f, $e0, $1f, $80
	db $7f, $80, $7f, $f7, $08, $eb, $14, $f7, $08, $f7, $08, $e3, $1c, $e3, $1c, $63
	db $9c, $01, $fe, $00, $00, $60, $60, $70, $70, $78, $78, $78, $78, $70, $70, $60
	db $60, $00, $00, $00, $00, $30, $30, $70, $70, $30, $30, $30, $30, $30, $30, $78
	db $78, $00, $00, $e0, $e0, $f0, $e0, $fb, $e0, $fc, $e0, $fc, $e1, $fc, $e1, $fc
	db $e1, $fc, $e1, $00, $00, $00, $00, $ff, $00, $00, $00, $00, $ff, $00, $00, $00
	db $00, $00, $00, $07, $07, $0f, $07, $df, $07, $3f, $07, $3f, $87, $3f, $87, $3f
	db $87, $3f, $87, $fc, $e1, $fc, $e1, $fc, $e1, $fc, $e1, $fc, $e1, $fc, $e1, $fc
	db $e1, $fc, $e1, $3f, $87, $3f, $87, $3f, $87, $3f, $87, $3f, $87, $3f, $87, $3f
	db $87, $3f, $87, $fc, $e1, $fc, $e1, $fc, $e1, $fc, $e1, $fc, $e0, $ff, $e7, $ff
	db $ef, $e0, $ff, $00, $00, $00, $00, $00, $00, $00, $ff, $00, $00, $ff, $ff, $ff
	db $ff, $00, $ff, $3f, $87, $3f, $87, $3f, $87, $3f, $87, $3f, $07, $ff, $e7, $ff
	db $f7, $07, $ff, $f8, $00, $e0, $00, $c0, $00, $80, $00, $80, $00, $00, $00, $00
	db $00, $00, $00, $7f, $00, $1f, $00, $0f, $00, $07, $00, $07, $00, $03, $00, $03
	db $00, $03, $00, $00, $00, $80, $00, $80, $00, $c0, $00, $e0, $00, $f8, $00, $ff
	db $00, $ff, $00, $03, $00, $07, $00, $07, $00, $0f, $00, $1f, $00, $7f, $00, $ff
	db $00, $ff, $00, $01, $01, $01, $01, $81, $81, $c1, $c1, $c1, $c1, $e1, $e1, $f1
	db $f1, $f9, $f9, $fe, $fe, $fe, $fe, $fe, $fe, $fe, $fe, $fe, $fe, $fe, $fe, $fe
	db $fe, $fe, $fe, $7e, $7e, $7f, $7f, $7f, $7f, $7f, $7f, $7f, $7f, $7f, $7f, $7f
	db $7f, $7f, $7f, $7f, $7f, $3f, $3f, $9f, $9f, $8f, $8f, $cf, $cf, $e7, $e7, $f3
	db $f3, $f7, $f7, $e0, $e0, $e0, $e0, $e0, $e0, $e0, $e0, $e0, $e0, $c0, $c0, $c0
	db $c0, $80, $80, $f0, $f0, $f0, $f0, $f0, $f0, $f0, $f0, $f0, $f0, $f0, $f0, $f0
	db $f0, $f0, $f0, $00, $00, $7c, $7c, $47, $47, $41, $41, $40, $40, $40, $40, $40
	db $40, $7f, $40, $00, $00, $01, $01, $01, $01, $81, $81, $c1, $c1, $41, $41, $61
	db $61, $e1, $61, $00, $00, $fe, $fe, $06, $06, $06, $06, $06, $06, $06, $06, $06
	db $06, $fe, $06, $00, $00, $1b, $1b, $32, $32, $59, $59, $4c, $4c, $8c, $8c, $86
	db $86, $ff, $83, $00, $00, $ff, $ff, $01, $01, $01, $01, $81, $81, $41, $41, $41
	db $41, $3f, $21, $00, $00, $be, $be, $88, $88, $88, $88, $88, $88, $88, $88, $80
	db $80, $80, $80, $00, $00, $88, $88, $d8, $d8, $a8, $a8, $88, $88, $88, $88, $00
	db $00, $00, $00, $7f, $40, $7f, $40, $7f, $40, $7f, $40, $7f, $40, $7f, $40, $7f
	db $40, $47, $7f, $e1, $61, $e1, $61, $e1, $61, $e1, $61, $e1, $61, $c1, $c1, $c1
	db $c1, $81, $81, $fe, $06, $fe, $06, $fe, $06, $fe, $06, $fe, $06, $fe, $06, $fe
	db $06, $06, $fe, $ff, $83, $ff, $81, $7f, $40, $7f, $40, $7f, $40, $3f, $20, $3f
	db $20, $10, $1f, $1f, $11, $9f, $91, $cf, $c9, $c7, $c5, $e3, $63, $f3, $33, $f9
	db $19, $08, $f8, $80, $80, $80, $80, $80, $80, $80, $80, $80, $80, $80, $80, $80
	db $80, $80, $80, $5f, $7f, $78, $78, $60, $60, $50, $70, $50, $70, $48, $78, $44
	db $7c, $7e, $7e, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
	db $01, $01, $01, $06, $fe, $06, $fe, $06, $fe, $06, $fe, $06, $fe, $06, $fe, $06
	db $fe, $fe, $fe, $08, $0f, $44, $47, $64, $67, $72, $73, $51, $71, $59, $79, $4c
	db $7c, $7e, $7e, $0c, $fc, $06, $fe, $03, $ff, $01, $ff, $01, $ff, $00, $ff, $80
	db $ff, $7f, $7f, $00, $00, $00, $00, $00, $00, $80, $80, $80, $80, $c0, $c0, $c0
	db $c0, $e0, $e0, $7e, $7e, $7f, $7f, $7f, $7f, $7f, $7f, $7f, $7f, $7f, $7f, $7f
	db $7f, $7f, $7f, $00, $00, $03, $03, $02, $02, $02, $02, $02, $02, $02, $02, $02
	db $02, $03, $02, $00, $00, $fb, $fb, $0a, $0a, $12, $12, $22, $22, $22, $22, $42
	db $42, $c3, $42, $00, $00, $fd, $fd, $0d, $0d, $0c, $0c, $0c, $0c, $0c, $0c, $0c
	db $0c, $fc, $0c, $00, $00, $fc, $fc, $0c, $0c, $8c, $8c, $4c, $4c, $4c, $4c, $2c
	db $2c, $3c, $2c, $03, $02, $03, $02, $03, $03, $03, $03, $02, $02, $00, $00, $00
	db $00, $00, $00, $83, $82, $83, $82, $03, $02, $03, $02, $03, $02, $03, $02, $03
	db $02, $02, $03, $fc, $0c, $fc, $0c, $fc, $0c, $fc, $0c, $fc, $0c, $fc, $0c, $fc
	db $0c, $0c, $fc, $1c, $1c, $1c, $1c, $0c, $0c, $0c, $0c, $04, $04, $00, $00, $00
	db $00, $00, $00, $02, $03, $02, $03, $02, $03, $02, $03, $02, $03, $02, $03, $02
	db $03, $03, $03, $0c, $fc, $0c, $fc, $0c, $fc, $0c, $fc, $0c, $fc, $0c, $fc, $0c
	db $fc, $fc, $fc, $03, $03, $03, $03, $03, $03, $03, $03, $03, $03, $03, $03, $03
	db $03, $03, $03, $fc, $fc, $fc, $fc, $fc, $fc, $fc, $fc, $fc, $fc, $fc, $fc, $fc
	db $fc, $fc, $fc, $ff, $00, $ff, $00, $ff, $00, $ff, $00, $ff, $00, $ff, $00, $ff
	db $00, $ff, $00, $00, $ff, $00, $ff, $00, $ff, $00, $ff, $00, $ff, $00, $ff, $00
	db $ff, $00, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff
	db $ff, $ff, $ff, $00, $00, $01, $01, $03, $03, $07, $07, $0f, $0f, $1f, $1f, $3f
	db $3f, $7f, $7f, $00, $00, $ff, $ff, $83, $83, $83, $83, $83, $83, $83, $83, $83
	db $83, $ff, $83, $00, $00, $7f, $7f, $20, $20, $10, $10, $08, $08, $04, $04, $02
	db $02, $01, $01, $00, $00, $f3, $f3, $32, $32, $32, $32, $32, $32, $32, $32, $32
	db $32, $f3, $32, $ff, $83, $ff, $83, $ff, $83, $ff, $83, $ff, $83, $ff, $83, $ff
	db $83, $83, $ff, $00, $00, $00, $00, $01, $01, $03, $03, $07, $07, $0f, $0b, $1f
	db $13, $23, $3f, $f3, $b2, $73, $72, $33, $33, $13, $13, $02, $02, $00, $00, $00
	db $00, $00, $00, $83, $ff, $83, $ff, $83, $ff, $83, $ff, $83, $ff, $83, $ff, $83
	db $ff, $ff, $ff, $43, $7f, $23, $3f, $13, $1f, $0b, $0f, $07, $07, $03, $03, $01
	db $01, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $10, $10, $30
	db $30, $70, $70, $00, $00, $78, $78, $9c, $9c, $1c, $1c, $78, $78, $e0, $e0, $fc
	db $fc, $00, $00, $ff, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
	db $00, $00, $00, $1b, $1b, $1b, $1b, $09, $09, $00, $00, $00, $00, $00, $00, $00
	db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $60, $60, $60, $60, $20
	db $20, $00, $00, $1b, $1b, $1b, $1b, $09, $09, $00, $00, $00, $00, $60, $60, $60
	db $60, $00, $00

;@ asset: tilemap width=20 height=18 tiles=LoadTitleTiles
;@ Full screen shown by the first game state (State24_CopyrightScreen).
CopyrightScreenTilemap::
	db $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f
	db $2f, $2f, $2f, $2f, $2f, $2f, $2f, $9b, $1d, $16, $2f, $0a, $17, $0d, $2f, $33
	db $01, $09, $08, $07, $2f, $0e, $15, $18, $1b, $10, $9c, $2f, $1d, $0e, $1d, $1b
	db $12, $1c, $2f, $15, $12, $0c, $0e, $17, $1c, $0e, $0d, $2f, $1d, $18, $2f, $2f
	db $2f, $2f, $2f, $0b, $1e, $15, $15, $0e, $1d, $25, $19, $1b, $18, $18, $0f, $2f
	db $2f, $2f, $2f, $2f, $2f, $2f, $2f, $1c, $18, $0f, $1d, $20, $0a, $1b, $0e, $2f
	db $0a, $17, $0d, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $1c, $1e, $0b, $25, $15, $12
	db $0c, $0e, $17, $1c, $0e, $0d, $2f, $1d, $18, $2f, $2f, $2f, $2f, $2f, $2f, $2f
	db $2f, $17, $12, $17, $1d, $0e, $17, $0d, $18, $24, $2f, $2f, $2f, $2f, $2f, $2f
	db $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f
	db $2f, $2f, $2f, $2f, $33, $01, $09, $08, $09, $2f, $0b, $1e, $15, $15, $0e, $1d
	db $25, $19, $1b, $18, $18, $0f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $1c, $18, $0f
	db $1d, $20, $0a, $1b, $0e, $24, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $33, $30
	db $31, $32, $31, $2f, $34, $35, $36, $37, $38, $39, $2f, $2f, $2f, $2f, $2f, $2f
	db $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f
	db $2f, $2f, $2f, $0a, $15, $15, $2f, $1b, $12, $10, $11, $1d, $1c, $2f, $1b, $0e
	db $1c, $0e, $1b, $1f, $0e, $0d, $24, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f
	db $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $18, $1b, $12
	db $10, $12, $17, $0a, $15, $2f, $0c, $18, $17, $0c, $0e, $19, $1d, $9c, $2f, $2f
	db $0d, $0e, $1c, $12, $10, $17, $2f, $0a, $17, $0d, $2f, $19, $1b, $18, $10, $1b
	db $0a, $16, $2f, $0b, $22, $2f, $0a, $15, $0e, $21, $0e, $22, $2f, $19, $0a, $23
	db $11, $12, $1d, $17, $18, $1f, $9d, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f
	db $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f

;@ asset: tilemap width=20 height=18 tiles=LoadTitleTiles
;@ Full screen loaded by State06_TitleScreenInit.
TitleScreenTilemap::
	db $8e, $8e, $8e, $8e, $8e
	db $8e, $8e, $8e, $8e, $8e, $8e, $8e, $8e, $8e, $8e, $8e, $8e, $8e, $8e, $8e, $5a
	db $5b, $5b, $5b, $5b, $5b, $5b, $5b, $5b, $5b, $5b, $5b, $5b, $5b, $5b, $5b, $5b
	db $5b, $5b, $5c, $5d, $80, $81, $82, $83, $90, $91, $92, $81, $82, $83, $90, $6c
	db $6d, $6e, $6f, $70, $71, $72, $5e, $5d, $84, $85, $86, $87, $93, $94, $95, $85
	db $86, $87, $93, $73, $74, $75, $76, $77, $78, $2f, $5e, $5d, $2f, $88, $89, $2f
	db $96, $97, $98, $88, $89, $2f, $96, $79, $7a, $7b, $7c, $7d, $7e, $2f, $5e, $5d
	db $2f, $8a, $8b, $2f, $8e, $8f, $6b, $8a, $8b, $2f, $8e, $7f, $66, $67, $68, $69
	db $6a, $2f, $5e, $5f, $60, $60, $60, $60, $60, $60, $60, $60, $60, $60, $60, $60
	db $60, $60, $60, $60, $60, $60, $61, $8e, $3c, $3c, $3c, $3c, $3c, $3c, $3c, $3c
	db $3c, $3c, $3c, $3c, $3c, $3d, $3e, $3c, $3c, $3c, $8e, $8e, $8c, $8c, $62, $63
	db $8c, $8c, $3a, $8c, $8c, $8c, $8c, $8c, $3a, $42, $43, $3b, $8c, $8c, $8e, $8e
	db $3a, $8c, $64, $65, $8c, $8c, $8c, $8c, $3b, $8c, $8c, $8c, $8c, $44, $45, $8c
	db $8c, $8c, $8e, $8e, $8c, $8c, $8c, $8c, $8c, $8c, $8c, $8c, $8c, $8c, $8c, $8c
	db $46, $47, $48, $49, $3f, $40, $8e, $8e, $8c, $8c, $8c, $8c, $3a, $8c, $8c, $8c
	db $8c, $53, $54, $8c, $4a, $4b, $4c, $4d, $42, $43, $8e, $8e, $8c, $8c, $8c, $8c
	db $8c, $8c, $8c, $8c, $54, $55, $56, $57, $4e, $4f, $50, $51, $52, $45, $8e, $41
	db $41, $41, $41, $41, $41, $41, $41, $41, $41, $41, $41, $41, $41, $41, $41, $41
	db $41, $41, $41, $2f, $2f, $59, $19, $15, $0a, $22, $0e, $1b, $2f, $2f, $2f, $99
	db $19, $15, $0a, $22, $0e, $1b, $2f, $2f, $2f, $9a, $9a, $9a, $9a, $9a, $9a, $9a
	db $2f, $2f, $2f, $9a, $9a, $9a, $9a, $9a, $9a, $9a, $2f, $2f, $2f, $2f, $2f, $33
	db $30, $31, $32, $31, $2f, $34, $35, $36, $37, $38, $39, $2f, $2f, $2f, $2f, $2f
	db $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f
	db $2f, $2f, $2f

;@ asset: tilemap width=20 height=18 tiles=LoadGameTiles
;@ Full screen loaded by State07_TitleScreen and ShowGameMenu.
GameMusicTypeTilemap::
	db $47, $48, $48, $48, $48, $48, $48, $48, $48, $48, $48, $48, $48
	db $48, $48, $48, $48, $48, $48, $49, $4a, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c
	db $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $4b, $4a, $2c, $2c, $2c, $50
	db $51, $51, $51, $51, $51, $51, $51, $51, $51, $52, $2c, $2c, $2c, $2c, $4b, $4a
	db $2c, $2c, $2c, $53, $10, $0a, $16, $0e, $2f, $1d, $22, $19, $0e, $54, $2c, $2c
	db $2c, $2c, $4b, $4a, $2c, $55, $56, $6d, $58, $58, $58, $58, $58, $a9, $58, $58
	db $58, $6e, $56, $56, $5a, $2c, $4b, $4a, $2c, $5b, $78, $77, $7e, $7f, $9a, $9b
	db $2f, $aa, $79, $77, $7e, $7f, $9a, $9b, $5c, $2c, $4b, $4a, $2c, $2d, $4f, $4f
	db $4f, $4f, $4f, $4f, $4f, $ac, $4f, $4f, $4f, $4f, $4f, $4f, $2e, $2c, $4b, $4a
	db $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c
	db $2c, $2c, $4b, $4a, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c
	db $2c, $2c, $2c, $2c, $2c, $2c, $4b, $4a, $2c, $2c, $2c, $50, $51, $51, $51, $51
	db $51, $51, $51, $51, $51, $51, $52, $2c, $2c, $2c, $4b, $4a, $2c, $2c, $2c, $53
	db $16, $1e, $1c, $12, $0c, $2f, $1d, $22, $19, $0e, $54, $2c, $2c, $2c, $4b, $4a
	db $2c, $55, $56, $6d, $58, $58, $58, $58, $58, $a9, $58, $58, $58, $58, $6e, $56
	db $5a, $2c, $4b, $4a, $2c, $5b, $78, $77, $7e, $7f, $9a, $9b, $2f, $aa, $79, $77
	db $7e, $7f, $9a, $9b, $5c, $2c, $4b, $4a, $2c, $71, $72, $72, $72, $72, $72, $72
	db $72, $ab, $72, $72, $72, $72, $72, $72, $74, $2c, $4b, $4a, $2c, $5b, $7a, $77
	db $7e, $7f, $9a, $9b, $2f, $aa, $2f, $9d, $9c, $9c, $2f, $2f, $5c, $2c, $4b, $4a
	db $2c, $2d, $4f, $4f, $4f, $4f, $4f, $4f, $4f, $ac, $4f, $4f, $4f, $4f, $4f, $4f
	db $2e, $2c, $4b, $4a, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c
	db $2c, $2c, $2c, $2c, $2c, $2c, $4b, $4c, $4d, $4d, $4d, $4d, $4d, $4d, $4d, $4d
	db $4d, $4d, $4d, $4d, $4d, $4d, $4d, $4d, $4d, $4d, $4e

;@ asset: tilemap width=20 height=18 tiles=LoadGameTiles
;@ Full screen loaded by State10_TypeALevelInit.
TypeALevelSelectTilemap::
	db $47, $48, $48, $48, $48
	db $48, $48, $48, $48, $48, $48, $48, $48, $48, $48, $48, $48, $48, $48, $49, $4a
	db $2f, $0a, $25, $1d, $22, $19, $0e, $2f, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c
	db $2c, $2c, $4b, $4a, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c
	db $2c, $2c, $2c, $2c, $2c, $2c, $4b, $4a, $2c, $2c, $2c, $2c, $2c, $50, $51, $51
	db $51, $51, $51, $52, $2c, $2c, $2c, $2c, $2c, $2c, $4b, $4a, $2c, $2c, $2c, $2c
	db $2c, $53, $15, $0e, $1f, $0e, $15, $54, $2c, $2c, $2c, $2c, $2c, $2c, $4b, $4a
	db $2c, $2c, $2c, $55, $56, $57, $58, $6c, $58, $6c, $58, $59, $56, $5a, $2c, $2c
	db $2c, $2c, $4b, $4a, $2c, $2c, $2c, $5b, $90, $6f, $91, $6f, $92, $6f, $93, $6f
	db $94, $5c, $2c, $2c, $2c, $2c, $4b, $4a, $2c, $2c, $2c, $71, $72, $73, $72, $73
	db $72, $73, $72, $73, $72, $74, $2c, $2c, $2c, $2c, $4b, $4a, $2c, $2c, $2c, $5b
	db $95, $6f, $96, $6f, $97, $6f, $98, $6f, $99, $5c, $2c, $2c, $2c, $2c, $4b, $4a
	db $2c, $2c, $2c, $2d, $4f, $6b, $4f, $6b, $4f, $6b, $4f, $6b, $4f, $2e, $2c, $2c
	db $2c, $2c, $4b, $4a, $2c, $2c, $2c, $50, $51, $51, $51, $51, $51, $51, $51, $51
	db $51, $52, $2c, $2c, $2c, $2c, $4b, $4a, $2c, $2c, $2c, $53, $1d, $18, $19, $25
	db $1c, $0c, $18, $1b, $0e, $54, $2c, $2c, $2c, $2c, $4b, $4a, $55, $56, $70, $6d
	db $58, $58, $58, $58, $58, $58, $58, $58, $58, $6e, $56, $56, $56, $5a, $4b, $4a
	db $5b, $01, $6f, $60, $60, $60, $60, $60, $60, $2f, $2f, $60, $60, $60, $60, $60
	db $60, $5c, $4b, $4a, $5b, $02, $6f, $60, $60, $60, $60, $60, $60, $2f, $2f, $60
	db $60, $60, $60, $60, $60, $5c, $4b, $4a, $5b, $03, $6f, $60, $60, $60, $60, $60
	db $60, $2f, $2f, $60, $60, $60, $60, $60, $60, $5c, $4b, $4a, $2d, $4f, $6b, $4f
	db $4f, $4f, $4f, $4f, $4f, $4f, $4f, $4f, $4f, $4f, $4f, $4f, $4f, $2e, $4b, $4c
	db $4d, $4d, $4d, $4d, $4d, $4d, $4d, $4d, $4d, $4d, $4d, $4d, $4d, $4d, $4d, $4d
	db $4d, $4d, $4e

;@ asset: tilemap width=20 height=18 tiles=LoadGameTiles
;@ Full screen loaded by State12_TypeBLevelInit.
TypeBLevelSelectTilemap::
	db $47, $48, $48, $48, $48, $48, $48, $48, $48, $48, $48, $48, $48
	db $48, $48, $48, $48, $48, $48, $49, $4a, $2f, $0b, $25, $1d, $22, $19, $0e, $2f
	db $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $4b, $4a, $2c, $2c, $2c, $2c
	db $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $4b, $4a
	db $2c, $2c, $50, $51, $51, $51, $51, $51, $52, $2c, $2c, $50, $51, $51, $51, $51
	db $52, $2c, $4b, $4a, $2c, $2c, $53, $15, $0e, $1f, $0e, $15, $54, $2c, $2c, $53
	db $11, $12, $10, $11, $54, $2c, $4b, $4a, $55, $56, $57, $58, $6c, $58, $6c, $58
	db $59, $56, $5a, $75, $58, $6c, $58, $6c, $6e, $5a, $4b, $4a, $5b, $90, $6f, $91
	db $6f, $92, $6f, $93, $6f, $94, $5c, $5b, $90, $6f, $91, $6f, $92, $5c, $4b, $4a
	db $71, $72, $73, $72, $73, $72, $73, $72, $73, $72, $74, $71, $72, $73, $72, $73
	db $72, $74, $4b, $4a, $5b, $95, $6f, $96, $6f, $97, $6f, $98, $6f, $99, $5c, $5b
	db $93, $6f, $94, $6f, $95, $5c, $4b, $4a, $2d, $4f, $6b, $4f, $6b, $4f, $6b, $4f
	db $6b, $4f, $2e, $2d, $4f, $6b, $4f, $6b, $4f, $2e, $4b, $4a, $2c, $2c, $2c, $50
	db $51, $51, $51, $51, $51, $51, $51, $51, $51, $52, $2c, $2c, $2c, $2c, $4b, $4a
	db $2c, $2c, $2c, $53, $1d, $18, $19, $25, $1c, $0c, $18, $1b, $0e, $54, $2c, $2c
	db $2c, $2c, $4b, $4a, $55, $56, $70, $6d, $58, $58, $58, $58, $58, $58, $58, $58
	db $58, $6e, $56, $56, $56, $5a, $4b, $4a, $5b, $01, $6f, $60, $60, $60, $60, $60
	db $60, $2f, $2f, $60, $60, $60, $60, $60, $60, $5c, $4b, $4a, $5b, $02, $6f, $60
	db $60, $60, $60, $60, $60, $2f, $2f, $60, $60, $60, $60, $60, $60, $5c, $4b, $4a
	db $5b, $03, $6f, $60, $60, $60, $60, $60, $60, $2f, $2f, $60, $60, $60, $60, $60
	db $60, $5c, $4b, $4a, $2d, $4f, $6b, $4f, $4f, $4f, $4f, $4f, $4f, $4f, $4f, $4f
	db $4f, $4f, $4f, $4f, $4f, $2e, $4b, $4c, $4d, $4d, $4d, $4d, $4d, $4d, $4d, $4d
	db $4d, $4d, $4d, $4d, $4d, $4d, $4d, $4d, $4d, $4d, $4e

; Board text for the dancers ending (10 x 18 tiles)
DancersText::
	db $cd, $cd, $cd, $cd, $cd
	db $cd, $cd, $cd, $cd, $cd, $8c, $c9, $ca, $8c, $8c, $8c, $8c, $8c, $8c, $8c, $8c
	db $cb, $cc, $8c, $8c, $8c, $8c, $8c, $8c, $ce, $d7, $d7, $d7, $d7, $d7, $d7, $d7
	db $d7, $d7, $cf, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $d0, $2f, $2f, $2f
	db $2f, $2f, $2f, $2f, $2f, $d1, $d2, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $d3
	db $d4, $7c, $7c, $7c, $7c, $7c, $7c, $2f, $2f, $d5, $d6, $7d, $7d, $7d, $7d, $2f
	db $2f, $2f, $2f, $d8, $2f, $7b, $7b, $7b, $7b, $2f, $2f, $2f, $2f, $d8, $2f, $7c
	db $7c, $7c, $7c, $2f, $2f, $2f, $2f, $d8, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f
	db $2f, $d8, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $7c, $7c, $7c, $7c, $2f, $2f, $2f
	db $2f, $2f, $2f, $2f, $2f, $2f, $7c, $7d, $7d, $2f, $2f, $2f, $2f, $2f, $2f, $2f
	db $7d, $2f, $2f, $2f, $d9, $2f, $2f, $2f, $2f, $2f, $7b, $b7, $b8, $d9, $b7, $2f
	db $7c, $7c, $7c, $7c, $7c, $7d, $7d, $7d, $7d, $7d, $7d, $7d, $7d, $7d, $7d, $ff
;@ asset: tilemap width=20 height=4 tiles=LoadTilesToVRAM(hl=CutsceneTiles,bc=$1000)
;@ Drawn by ShowLaunchPad (4 rows at $9DC0).
LaunchPadTilemap::
	db $4a, $4a, $4a, $4a, $4a, $4a, $59, $69, $69, $69, $69, $69, $69, $49, $4a, $4a
	db $4a, $4a, $4a, $4a, $5a, $5a, $5a, $5a, $5a, $5a, $85, $85, $85, $85, $85, $85
	db $85, $85, $5a, $5a, $38, $39, $38, $5a, $6a, $6a, $6a, $6a, $6a, $6a, $6a, $6a
	db $6a, $6a, $6a, $6a, $6a, $6a, $6a, $6a, $6a, $6a, $6a, $6a, $07, $07, $07, $07
	db $07, $07, $07, $07, $07, $07, $07, $07, $07, $07, $07, $07, $07, $07, $07, $07
;@ asset: tilemap width=20 height=18 tiles=LoadGameTiles
;@ Full screen loaded by State16_VersusHeightInit.
VersusSetupTilemap::
	db $47, $48, $48, $48, $48, $48, $48, $48, $48, $48, $48, $48, $48, $48, $48, $48
	db $48, $48, $48, $49, $4a, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c
	db $2c, $2c, $2c, $2c, $2c, $2c, $2c, $4b, $4a, $2c, $2c, $16, $0a, $1b, $12, $18
	db $2f, $1f, $1c, $24, $15, $1e, $12, $10, $12, $2c, $2c, $4b, $4a, $2c, $2c, $2c
	db $2c, $2c, $2c, $2c, $2c, $2c, $50, $51, $51, $51, $51, $52, $2c, $2c, $2c, $4b
	db $4a, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $2c, $53, $11, $12, $10, $11, $54
	db $2c, $2c, $2c, $4b, $4a, $2c, $2c, $55, $56, $56, $5a, $2c, $2c, $2c, $75, $58
	db $6c, $58, $6c, $6e, $5a, $2c, $2c, $4b, $4a, $2c, $2c, $5b, $2f, $2f, $5c, $2c
	db $2c, $2c, $5b, $90, $6f, $91, $6f, $92, $5c, $2c, $2c, $4b, $4a, $2c, $2c, $5b
	db $2f, $2f, $5c, $2c, $2c, $2c, $71, $72, $73, $72, $73, $72, $74, $2c, $2c, $4b
	db $4a, $2c, $2c, $2d, $4f, $4f, $2e, $2c, $2c, $2c, $5b, $93, $6f, $94, $6f, $95
	db $5c, $2c, $2c, $4b, $4a, $2c, $2c, $16, $0a, $1b, $12, $18, $2c, $2c, $2d, $4f
	db $6b, $4f, $6b, $4f, $2e, $2c, $2c, $4b, $4a, $2c, $2c, $2c, $2c, $2c, $2c, $2c
	db $2c, $2c, $50, $51, $51, $51, $51, $52, $2c, $2c, $2c, $4b, $4a, $2c, $2c, $2c
	db $2c, $2c, $2c, $2c, $2c, $2c, $53, $11, $12, $10, $11, $54, $2c, $2c, $2c, $4b
	db $4a, $2c, $2c, $55, $56, $56, $5a, $2c, $2c, $2c, $75, $58, $6c, $58, $6c, $6e
	db $5a, $2c, $2c, $4b, $4a, $2c, $2c, $5b, $2f, $2f, $5c, $2c, $2c, $2c, $5b, $90
	db $6f, $91, $6f, $92, $5c, $2c, $2c, $4b, $4a, $2c, $2c, $5b, $2f, $2f, $5c, $2c
	db $2c, $2c, $71, $72, $73, $72, $73, $72, $74, $2c, $2c, $4b, $4a, $2c, $2c, $2d
	db $4f, $4f, $2e, $2c, $2c, $2c, $5b, $93, $6f, $94, $6f, $95, $5c, $2c, $2c, $4b
	db $4a, $2c, $2c, $15, $1e, $12, $10, $12, $2c, $2c, $2d, $4f, $6b, $4f, $6b, $4f
	db $2e, $2c, $2c, $4b, $4c, $4d, $4d, $4d, $4d, $4d, $4d, $4d, $4d, $4d, $4d, $4d
	db $4d, $4d, $4d, $4d, $4d, $4d, $4d, $4e

; The 2-player game screen
VersusGameScreen::
	db $8e, $b2, $2f, $2f, $2f, $2f, $2f, $2f
	db $2f, $2f, $2f, $2f, $b3, $30, $31, $31, $31, $31, $31, $32, $8e, $b0, $2f, $2f
	db $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $b5, $36, $2f, $2f, $2f, $2f, $2f, $37
	db $8e, $b0, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $b5, $36, $2f, $2f
	db $2f, $2f, $2f, $37, $8e, $b0, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f
	db $b5, $40, $42, $42, $42, $42, $42, $41, $8e, $b0, $2f, $2f, $2f, $2f, $2f, $2f
	db $2f, $2f, $2f, $2f, $b5, $36, $11, $12, $10, $11, $2f, $37, $8e, $b0, $2f, $2f
	db $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $b5, $36, $2f, $2f, $2f, $2f, $2f, $37
	db $8e, $b0, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $b5, $33, $34, $34
	db $34, $34, $34, $35, $8e, $b0, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f
	db $b5, $2b, $8e, $8e, $8e, $8e, $8e, $8e, $8e, $b0, $2f, $2f, $2f, $2f, $2f, $2f
	db $2f, $2f, $2f, $2f, $b5, $30, $31, $31, $31, $31, $31, $32, $8e, $b0, $2f, $2f
	db $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $b5, $36, $15, $12, $17, $0e, $1c, $37
	db $8e, $b0, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $b5, $36, $2f, $2f
	db $2f, $2f, $2f, $37, $8e, $b0, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f
	db $b5, $33, $34, $34, $34, $34, $34, $35, $8e, $b0, $2f, $2f, $2f, $2f, $2f, $2f
	db $2f, $2f, $2f, $2f, $b5, $2b, $38, $39, $39, $39, $39, $3a, $8e, $b0, $2f, $2f
	db $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $b5, $2b, $3b, $2f, $2f, $2f, $2f, $3c
	db $8e, $b0, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $b5, $2b, $3b, $2f
	db $2f, $2f, $2f, $3c, $8e, $b0, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f
	db $b5, $2b, $3b, $2f, $2f, $2f, $2f, $3c, $8e, $b0, $2f, $2f, $2f, $2f, $2f, $2f
	db $2f, $2f, $2f, $2f, $b5, $2b, $3b, $2f, $2f, $2f, $2f, $3c, $8e, $b1, $2f, $2f
	db $2f, $2f, $2f, $2f, $2f, $2f, $2f, $2f, $b4, $2b, $3d, $3e, $3e, $3e, $3e, $3f
;@ asset: tilemap width=20 height=10 tiles=LoadTilesToVRAM(hl=CutsceneTiles,bc=$1000)
;@ Drawn by ShowVersusTally in two parts: 4 rows at the top, 6 rows from $9980.
VersusTallyTilemap::
	db $07, $07, $07, $07, $07, $07, $84, $87, $87, $8c, $87, $87, $8c, $87, $87, $8c
	db $87, $87, $86, $07, $07, $1e, $1e, $1e, $1e, $1e, $79, $2f, $2f, $8d, $2f, $2f
	db $8d, $2f, $2f, $8d, $2f, $2f, $88, $07, $07, $b4, $b5, $bb, $2e, $bc, $79, $2f
	db $2f, $8d, $2f, $2f, $8d, $2f, $2f, $8d, $2f, $2f, $88, $07, $07, $bf, $bf, $bf
	db $bf, $bf, $89, $8a, $8a, $8e, $8a, $8a, $8e, $8a, $8a, $8e, $8a, $8a, $8b, $07
	db $06, $06, $06, $06, $06, $06, $06, $06, $06, $06, $06, $06, $06, $06, $06, $06
	db $06, $06, $06, $06, $16, $16, $16, $16, $16, $16, $16, $16, $16, $16, $16, $16
	db $16, $16, $16, $16, $16, $16, $16, $16, $07, $07, $07, $07, $07, $07, $84, $87
	db $87, $8c, $87, $87, $8c, $87, $87, $8c, $87, $87, $86, $07, $07, $1e, $1e, $1e
	db $1e, $1e, $79, $2f, $2f, $8d, $2f, $2f, $8d, $2f, $2f, $8d, $2f, $2f, $88, $07
	db $07, $bd, $b2, $2e, $be, $2e, $79, $2f, $2f, $8d, $2f, $2f, $8d, $2f, $2f, $8d
	db $2f, $2f, $88, $07, $07, $bf, $bf, $bf, $bf, $bf, $89, $8a, $8a, $8e, $8a, $8a
	db $8e, $8a, $8a, $8e, $8a, $8a, $8b, $07

;@ asset: tiles bpp=2 length=$1000
;@ A full 256-tile set, copied to $8000 by ShowVersusTally and ShowLaunchPad.
CutsceneTiles::
	db $01, $01, $01, $01, $01, $01, $02, $02
	db $03, $03, $01, $01, $01, $01, $02, $02, $00, $00, $00, $00, $00, $00, $00, $00
	db $07, $07, $18, $1f, $21, $3e, $47, $7f, $f2, $fe, $12, $1e, $12, $1e, $12, $1e
	db $7e, $7e, $ff, $83, $ff, $81, $ff, $ff, $00, $00, $00, $00, $00, $00, $00, $00
	db $07, $07, $18, $1f, $21, $3e, $47, $7f, $04, $fc, $02, $fe, $02, $fe, $07, $fd
	db $07, $fd, $1f, $ff, $ff, $ff, $ff, $fa, $00, $00, $00, $00, $00, $00, $00, $00
	db $00, $00, $00, $00, $07, $07, $18, $1f, $ff, $ff, $77, $11, $ff, $11, $ff, $ff
	db $dd, $44, $ff, $44, $ff, $ff, $77, $11, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff
	db $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $00, $00, $03, $03, $05, $04, $03, $03
	db $00, $00, $18, $18, $2c, $24, $1a, $1a, $08, $08, $40, $40, $07, $07, $18, $1f
	db $a0, $bf, $3b, $3f, $7c, $44, $7c, $44, $10, $10, $02, $02, $e0, $e0, $18, $f8
	db $05, $fd, $8c, $fc, $78, $48, $6c, $74, $00, $00, $07, $07, $18, $1f, $20, $3f
	db $30, $3f, $1f, $1d, $3e, $22, $3e, $22, $80, $80, $80, $80, $80, $80, $80, $80
	db $00, $00, $c0, $c0, $e0, $e0, $e0, $e0, $00, $00, $7c, $7c, $66, $66, $66, $66
	db $7c, $7c, $60, $60, $60, $60, $00, $00, $00, $00, $3c, $3c, $60, $60, $3c, $3c
	db $0e, $0e, $4e, $4e, $3c, $3c, $00, $00, $07, $07, $1f, $18, $3e, $20, $7f, $4f
	db $7f, $5f, $70, $70, $a2, $a2, $b0, $b0, $04, $04, $07, $04, $04, $04, $04, $0d
	db $04, $0d, $04, $04, $04, $04, $03, $02, $5f, $7f, $39, $30, $7b, $62, $fb, $b2
	db $ff, $a0, $ff, $c2, $7f, $54, $7f, $5c, $00, $00, $00, $00, $00, $00, $03, $03
	db $04, $04, $08, $08, $09, $09, $04, $04, $5f, $7f, $39, $30, $7b, $62, $fb, $b2
	db $ff, $a0, $ff, $c2, $7f, $54, $7f, $5c, $18, $f8, $04, $fc, $02, $fe, $02, $fe
	db $07, $fd, $07, $fd, $ff, $ff, $ff, $fa, $20, $3f, $40, $7f, $40, $7f, $e0, $bf
	db $e0, $bf, $f8, $ff, $7f, $7f, $7f, $5f, $ff, $11, $ff, $ff, $dd, $44, $ff, $44
	db $ff, $ff, $77, $11, $ff, $11, $ff, $ff, $00, $00, $00, $00, $00, $00, $00, $00
	db $00, $00, $00, $00, $80, $80, $c0, $40, $00, $00, $00, $00, $00, $00, $04, $04
	db $08, $08, $1c, $14, $14, $14, $08, $08, $18, $1f, $20, $3f, $40, $7f, $40, $7f
	db $e0, $bf, $e0, $bf, $7f, $7f, $7f, $5f, $dd, $44, $ff, $44, $ff, $ff, $77, $11
	db $ff, $11, $ff, $ff, $dd, $44, $ff, $44, $00, $00, $00, $00, $00, $00, $20, $20
	db $10, $10, $38, $28, $28, $28, $90, $90, $00, $00, $46, $46, $46, $46, $7e, $7e
	db $46, $46, $46, $46, $46, $46, $00, $00, $00, $00, $7e, $7e, $18, $18, $18, $18
	db $18, $18, $18, $18, $18, $18, $00, $00, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff
	db $ff, $ff, $ff, $ff, $00, $00, $00, $ee, $b4, $b4, $64, $64, $3c, $3c, $2e, $2e
	db $27, $27, $70, $70, $fc, $9c, $f7, $9f, $00, $00, $00, $00, $00, $00, $01, $01
	db $01, $01, $02, $02, $02, $02, $02, $02, $3f, $2e, $7f, $63, $ff, $98, $f7, $1f
	db $f7, $1c, $f7, $d7, $34, $3f, $ac, $bf, $03, $03, $01, $01, $01, $01, $00, $00
	db $00, $00, $06, $06, $05, $05, $07, $07, $ff, $ae, $ff, $23, $ff, $18, $f7, $9f
	db $f7, $9c, $77, $57, $34, $3f, $6c, $7f, $00, $00, $00, $00, $00, $00, $01, $01
	db $01, $01, $02, $02, $02, $02, $02, $02, $3f, $2f, $7f, $7c, $f7, $9c, $f3, $1f
	db $f0, $1f, $f0, $df, $30, $3f, $a0, $bf, $ff, $f4, $ff, $3e, $ef, $38, $cf, $f8
	db $0f, $fb, $0e, $fa, $0c, $fc, $04, $fc, $e0, $20, $e0, $20, $e0, $20, $c0, $40
	db $80, $80, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
	db $01, $01, $01, $01, $02, $02, $02, $02, $3f, $2f, $3f, $3c, $77, $5c, $f3, $9f
	db $f0, $1f, $f0, $1f, $f0, $ff, $20, $3f, $ff, $f4, $ff, $3e, $ef, $38, $cf, $f9
	db $0e, $fa, $0e, $fa, $0c, $fc, $04, $fc, $c0, $40, $c0, $40, $c0, $40, $80, $80
	db $00, $00, $00, $00, $00, $00, $00, $00, $f7, $1c, $f7, $34, $f7, $bf, $6c, $7f
	db $10, $1f, $50, $5f, $32, $3f, $f1, $ff, $00, $00, $46, $46, $46, $46, $56, $56
	db $7e, $7e, $6e, $6e, $46, $46, $00, $00, $00, $00, $3c, $3c, $18, $18, $18, $18
	db $18, $18, $18, $18, $3c, $3c, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
	db $00, $00, $00, $00, $00, $00, $00, $00, $02, $02, $01, $01, $00, $00, $00, $00
	db $00, $00, $00, $00, $00, $00, $00, $00, $40, $7f, $c0, $ff, $20, $3f, $22, $3f
	db $11, $1f, $72, $7e, $bf, $bf, $ff, $ff, $07, $07, $06, $07, $06, $07, $06, $07
	db $07, $07, $00, $00, $00, $00, $00, $00, $c0, $ff, $00, $ff, $00, $ff, $02, $ff
	db $ff, $ff, $00, $00, $00, $00, $00, $00, $02, $02, $01, $01, $00, $00, $00, $00
	db $00, $00, $00, $00, $00, $00, $00, $00, $40, $7f, $c0, $ff, $20, $3f, $20, $3f
	db $11, $1f, $72, $7e, $ff, $ff, $ff, $ff, $02, $fe, $02, $fe, $04, $fc, $04, $fc
	db $88, $f8, $4e, $7e, $ff, $ff, $ff, $ff, $00, $00, $00, $00, $80, $80, $40, $40
	db $00, $00, $00, $00, $00, $00, $07, $07, $00, $00, $00, $00, $ff, $00, $fd, $02
	db $cd, $32, $09, $f6, $08, $f7, $00, $ff, $00, $00, $00, $00, $ff, $00, $ff, $00
	db $ff, $00, $fc, $03, $cc, $33, $08, $f7, $7c, $44, $3f, $3f, $10, $1f, $10, $1f
	db $12, $1f, $19, $1f, $3f, $3f, $3e, $3e, $ce, $f2, $8e, $da, $09, $f9, $09, $f9
	db $4e, $fe, $98, $f8, $fc, $fc, $7c, $7c, $07, $07, $1f, $18, $3e, $20, $7f, $4f
	db $7f, $5f, $70, $70, $a2, $a2, $b0, $b0, $00, $00, $46, $46, $66, $66, $76, $76
	db $5e, $5e, $4e, $4e, $46, $46, $00, $00, $00, $00, $18, $18, $18, $18, $18, $18
	db $18, $18, $00, $00, $18, $18, $00, $00, $12, $1e, $12, $1e, $12, $1e, $12, $1e
	db $7e, $7e, $bf, $83, $ff, $81, $ff, $ff, $00, $00, $e0, $e0, $18, $f8, $04, $fc
	db $0c, $fc, $f8, $c8, $2c, $34, $2e, $32, $00, $00, $46, $46, $46, $46, $46, $46
	db $46, $46, $2c, $2c, $18, $18, $00, $00, $00, $00, $36, $36, $5f, $49, $5f, $41
	db $7f, $41, $3e, $22, $1c, $14, $08, $08, $fe, $02, $fd, $05, $fd, $05, $ff, $1f
	db $ff, $fc, $ff, $fe, $ef, $38, $ef, $39, $00, $04, $00, $04, $00, $04, $01, $05
	db $01, $05, $03, $07, $06, $06, $0c, $0c, $ca, $c0, $c8, $c0, $ca, $c0, $88, $80
	db $88, $87, $08, $00, $0a, $00, $08, $00, $6f, $13, $2f, $13, $6f, $13, $2f, $11
	db $2d, $d1, $2c, $10, $6c, $10, $2c, $10, $a0, $20, $a0, $20, $a0, $20, $a0, $a0
	db $a0, $a0, $e0, $e0, $60, $60, $30, $30, $08, $a8, $08, $18, $08, $a8, $08, $48
	db $08, $a8, $08, $18, $08, $a8, $08, $48, $00, $fe, $00, $ff, $7f, $ff, $7f, $c1
	db $7f, $c1, $7f, $eb, $7f, $c1, $01, $ff, $00, $00, $00, $00, $00, $00, $ff, $00
	db $00, $00, $ff, $00, $00, $00, $ff, $00, $10, $10, $0b, $0b, $07, $04, $07, $04
	db $03, $02, $01, $01, $00, $00, $00, $00, $b4, $b4, $e4, $e4, $bc, $bc, $ee, $6e
	db $e7, $27, $f0, $10, $fc, $9c, $77, $5f, $00, $00, $00, $00, $07, $07, $1f, $18
	db $3f, $20, $7f, $40, $7f, $40, $7f, $40, $00, $00, $00, $00, $00, $00, $80, $80
	db $c0, $40, $c0, $40, $c0, $40, $80, $80, $02, $03, $05, $04, $07, $04, $04, $07
	db $04, $07, $04, $06, $04, $05, $04, $07, $ce, $fa, $0c, $fc, $08, $f8, $08, $f8
	db $08, $f8, $08, $f8, $08, $f8, $88, $f8, $00, $3c, $00, $7e, $10, $67, $24, $c3
	db $24, $c3, $24, $c3, $24, $c3, $34, $c3, $00, $3c, $00, $66, $00, $e7, $2c, $c3
	db $3c, $c3, $3c, $c3, $3c, $42, $18, $66, $00, $00, $00, $00, $00, $00, $20, $20
	db $90, $90, $b8, $a8, $a8, $a8, $10, $10, $0a, $10, $06, $08, $02, $04, $00, $04
	db $00, $04, $00, $04, $00, $04, $00, $04, $17, $50, $28, $60, $2a, $60, $28, $60
	db $2a, $60, $28, $60, $28, $67, $68, $60, $de, $2b, $2e, $17, $6e, $17, $2e, $17
	db $6e, $17, $2e, $17, $2e, $d7, $2e, $17, $98, $48, $b0, $50, $a0, $60, $a0, $20
	db $a0, $20, $a0, $20, $a0, $20, $a0, $20, $08, $a8, $08, $18, $08, $a8, $08, $48
	db $08, $b8, $08, $3f, $08, $bf, $09, $7f, $00, $7f, $00, $ff, $7e, $ff, $7e, $c1
	db $7e, $c1, $7e, $eb, $7e, $c1, $00, $ff, $00, $00, $00, $00, $ff, $00, $ff, $00
	db $ff, $00, $ff, $00, $ff, $00, $ff, $00, $00, $00, $38, $38, $34, $24, $3c, $24
	db $3f, $27, $3c, $27, $3c, $27, $3f, $2f, $37, $3c, $17, $14, $17, $1f, $1c, $1f
	db $f0, $ff, $00, $ff, $02, $ff, $ff, $ff, $bf, $a0, $bf, $a0, $bf, $b8, $7f, $7f
	db $2f, $2f, $7f, $7f, $f7, $9c, $f7, $9c, $fd, $05, $fd, $05, $fd, $1d, $ff, $ff
	db $f7, $f4, $ff, $fe, $ef, $38, $ef, $38, $01, $01, $01, $01, $01, $01, $02, $02
	db $02, $02, $02, $02, $01, $01, $00, $00, $02, $02, $02, $02, $01, $01, $00, $00
	db $00, $00, $00, $00, $00, $00, $00, $00, $34, $c3, $3c, $43, $3c, $43, $18, $66
	db $18, $66, $08, $76, $08, $36, $08, $34, $18, $26, $18, $24, $18, $24, $08, $34
	db $00, $18, $00, $08, $00, $08, $00, $08, $00, $00, $0f, $0f, $1f, $10, $3c, $20
	db $70, $40, $73, $43, $67, $4c, $3f, $28, $00, $00, $80, $80, $dc, $5c, $3e, $22
	db $32, $e2, $b1, $c1, $c3, $4b, $27, $7c, $00, $00, $00, $00, $00, $00, $00, $00
	db $e0, $e0, $d0, $10, $d0, $d0, $e0, $20, $5c, $50, $7c, $50, $39, $30, $7c, $4c
	db $ee, $82, $c0, $84, $60, $43, $31, $26, $1f, $3c, $bb, $62, $f1, $41, $61, $41
	db $c3, $03, $f7, $04, $ee, $08, $9c, $60, $90, $10, $08, $08, $18, $18, $3c, $64
	db $f2, $c2, $e3, $60, $39, $20, $f2, $00, $00, $ff, $00, $ff, $ff, $ff, $ff, $00
	db $ff, $00, $ff, $00, $00, $ff, $00, $ff, $ff, $ff, $ff, $00, $ff, $ff, $00, $ff
	db $00, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $38, $38, $00, $00, $00, $00, $00, $00
	db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
	db $0e, $0e, $11, $11, $11, $11, $12, $12, $f3, $1f, $f0, $3f, $f0, $bf, $60, $7f
	db $10, $1f, $50, $5f, $30, $3f, $f1, $ff, $cf, $fb, $0c, $fc, $08, $f8, $08, $f8
	db $08, $f8, $08, $f8, $08, $f8, $88, $f8, $4e, $7a, $c9, $d9, $09, $f9, $0e, $fe
	db $48, $f8, $98, $f8, $fc, $fc, $7c, $7c, $a0, $bf, $40, $7f, $e0, $ff, $20, $3f
	db $11, $1f, $72, $7e, $ff, $ff, $ff, $ff, $00, $3c, $00, $1c, $00, $1c, $00, $18
	db $00, $08, $00, $00, $00, $00, $00, $00, $00, $ff, $00, $ab, $00, $55, $00, $ff
	db $00, $00, $00, $00, $00, $00, $00, $00, $00, $15, $00, $18, $00, $15, $00, $12
	db $00, $15, $00, $18, $00, $15, $00, $12, $40, $40, $40, $c0, $40, $40, $40, $40
	db $40, $40, $40, $c0, $40, $40, $40, $40, $0e, $32, $0e, $32, $0e, $32, $0e, $32
	db $0f, $33, $8f, $b3, $ce, $f3, $ee, $73, $00, $00, $00, $00, $00, $00, $00, $00
	db $00, $00, $00, $00, $80, $80, $c0, $40, $00, $00, $00, $00, $80, $80, $47, $47
	db $1f, $18, $3f, $20, $7f, $40, $7f, $40, $7f, $40, $bf, $a0, $bf, $a0, $bf, $b8
	db $7f, $7f, $3f, $3f, $77, $7c, $f7, $9c, $f2, $e6, $f2, $e6, $f2, $e6, $f2, $e6
	db $f2, $e6, $f2, $e6, $f2, $e6, $f2, $e6, $00, $00, $01, $01, $01, $01, $01, $01
	db $02, $02, $02, $02, $02, $02, $01, $01, $f3, $9f, $f0, $1f, $f0, $3f, $e0, $bf
	db $70, $7f, $10, $1f, $50, $5f, $31, $3f, $3e, $22, $1f, $1f, $10, $1f, $10, $1f
	db $12, $1f, $19, $1f, $3f, $3f, $3e, $3e, $12, $1e, $12, $1e, $12, $1e, $12, $1e
	db $7e, $7e, $ff, $83, $ff, $81, $ff, $ff, $01, $01, $01, $01, $01, $01, $02, $02
	db $02, $02, $02, $02, $01, $01, $00, $00, $60, $e0, $80, $80, $80, $80, $80, $80
	db $80, $80, $80, $80, $80, $80, $80, $80, $07, $04, $07, $04, $07, $04, $07, $04
	db $07, $04, $07, $04, $07, $04, $07, $04, $0b, $09, $0b, $0a, $0f, $0a, $17, $12
	db $17, $1c, $14, $17, $17, $14, $2f, $24, $00, $00, $70, $70, $8f, $8f, $98, $9f
	db $e0, $ff, $f0, $9f, $78, $57, $7f, $4c, $3b, $2f, $d0, $df, $f0, $ff, $c0, $ff
	db $c0, $ff, $ff, $ff, $00, $00, $00, $00, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $f8
	db $f8, $f0, $f2, $e1, $f5, $e3, $f2, $e6, $ff, $ff, $ff, $81, $c3, $81, $df, $85
	db $df, $85, $ff, $bd, $ff, $81, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $1f
	db $1f, $0f, $4f, $87, $af, $c7, $4f, $67, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $00
	db $00, $00, $00, $ff, $ff, $ff, $00, $00, $4f, $67, $4f, $67, $4f, $67, $4f, $67
	db $4f, $67, $4f, $67, $4f, $67, $4f, $67, $f2, $e6, $f5, $e3, $f2, $e1, $f8, $f0
	db $ff, $f8, $ff, $ff, $ff, $ff, $ff, $ff, $00, $00, $ff, $ff, $00, $ff, $00, $00
	db $ff, $00, $ff, $ff, $ff, $ff, $ff, $ff, $4f, $67, $af, $c7, $4f, $87, $1f, $0f
	db $ff, $1f, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $00
	db $00, $00, $00, $ef, $e7, $cf, $24, $0c, $24, $0c, $24, $0c, $24, $0c, $24, $0c
	db $24, $0c, $24, $0c, $24, $0c, $24, $0c, $24, $0c, $e7, $cf, $00, $ef, $00, $00
	db $ff, $00, $ff, $ff, $ff, $ff, $ff, $ff, $07, $07, $18, $1f, $21, $3e, $47, $7f
	db $5f, $7f, $39, $30, $7b, $62, $fb, $b2, $e0, $e0, $18, $f8, $84, $7c, $e2, $fe
	db $fa, $fe, $9c, $0c, $de, $46, $df, $4d, $ff, $a0, $ff, $c2, $7f, $54, $7f, $5c
	db $3f, $2e, $3f, $23, $1f, $18, $07, $07, $ff, $05, $ff, $43, $fe, $2a, $fe, $3a
	db $fc, $74, $fc, $c4, $f8, $18, $e0, $e0, $07, $07, $1f, $18, $3e, $20, $7f, $4f
	db $7f, $5f, $70, $70, $a2, $a2, $b0, $b0, $e0, $e0, $f8, $18, $7c, $04, $fe, $f2
	db $fe, $fa, $0e, $0e, $45, $45, $0d, $0d, $b4, $b4, $64, $64, $3c, $3c, $2e, $2e
	db $27, $27, $10, $10, $0c, $0c, $03, $03, $2d, $2d, $26, $26, $3c, $3c, $74, $74
	db $e4, $e4, $08, $08, $30, $30, $c0, $c0, $2f, $24, $2f, $24, $2f, $24, $2f, $24
	db $67, $7c, $bc, $a7, $ff, $e4, $1b, $1b, $00, $00, $00, $00, $01, $01, $01, $01
	db $03, $03, $03, $03, $03, $02, $07, $04, $04, $07, $07, $04, $07, $04, $04, $04
	db $06, $06, $05, $05, $05, $05, $06, $06, $07, $04, $07, $04, $04, $07, $04, $04
	db $04, $04, $07, $07, $07, $07, $06, $06, $06, $06, $06, $06, $04, $04, $07, $07
	db $05, $05, $03, $03, $05, $05, $0e, $0e, $0f, $1f, $01, $10, $01, $10, $01, $10
	db $01, $08, $01, $07, $04, $09, $00, $0f, $08, $01, $f8, $f1, $4e, $c1, $02, $c7
	db $8c, $bd, $84, $ad, $62, $cf, $7e, $fe, $ec, $90, $ef, $9f, $fa, $f7, $da, $e7
	db $bd, $bd, $b5, $ad, $d2, $ef, $7f, $7f, $f8, $f8, $18, $e8, $38, $88, $b8, $08
	db $b0, $10, $e0, $e0, $d0, $30, $f0, $f0, $18, $18, $30, $30, $60, $60, $c0, $c0
	db $c0, $c0, $ff, $ff, $83, $83, $60, $62, $0a, $00, $08, $00, $08, $07, $08, $00
	db $08, $01, $f8, $f1, $f8, $f1, $08, $01, $6c, $10, $2c, $10, $2c, $d1, $2c, $11
	db $ac, $90, $ef, $9f, $ef, $9f, $ec, $90, $18, $18, $0c, $0c, $06, $c6, $03, $c3
	db $03, $03, $ff, $ff, $c1, $c1, $06, $46, $00, $04, $00, $0c, $02, $10, $02, $10
	db $02, $10, $02, $10, $02, $10, $02, $10, $0c, $4c, $0c, $4c, $09, $49, $0b, $4b
	db $0a, $4a, $10, $50, $12, $52, $10, $50, $7e, $33, $7e, $33, $be, $93, $fe, $d3
	db $7e, $53, $3e, $0b, $7e, $4b, $3e, $0b, $a0, $20, $90, $30, $98, $48, $98, $48
	db $98, $48, $98, $48, $98, $48, $98, $48, $00, $00, $00, $00, $00, $00, $00, $00
	db $01, $01, $01, $01, $02, $02, $02, $02, $02, $02, $02, $02, $02, $02, $00, $01
	db $02, $02, $02, $02, $02, $02, $02, $03, $02, $03, $02, $02, $02, $02, $02, $03
	db $02, $02, $06, $06, $0e, $0a, $0e, $0a, $0b, $0a, $0b, $0a, $0f, $0a, $0a, $0a
	db $06, $06, $0a, $0a, $1a, $12, $1f, $1f, $00, $00, $00, $00, $1f, $1f, $3f, $20
	db $7f, $47, $7c, $4c, $7c, $4c, $7c, $4c, $00, $00, $00, $00, $e0, $e0, $f0, $30
	db $f8, $18, $f8, $98, $f8, $98, $f8, $98, $7f, $4f, $7f, $40, $7f, $4f, $7c, $4c
	db $7c, $4c, $7c, $7c, $00, $00, $00, $00, $f8, $98, $f8, $18, $f8, $98, $f8, $98
	db $f8, $98, $f8, $f8, $00, $00, $00, $00, $00, $00, $7c, $7c, $4e, $4e, $4e, $4e
	db $4e, $4e, $4e, $4e, $7c, $7c, $00, $00, $00, $00, $7e, $7e, $60, $60, $7c, $7c
	db $60, $60, $60, $60, $7e, $7e, $00, $00, $00, $00, $46, $46, $46, $46, $46, $46
	db $46, $46, $4e, $4e, $3c, $3c, $00, $00, $00, $00, $3c, $3c, $66, $66, $60, $60
	db $60, $60, $66, $66, $3c, $3c, $00, $00, $00, $00, $46, $46, $6e, $6e, $7e, $7e
	db $56, $56, $46, $46, $46, $46, $00, $00, $00, $00, $3c, $3c, $4e, $4e, $4e, $4e
	db $7e, $7e, $4e, $4e, $4e, $4e, $00, $00, $ff, $00, $00, $00, $00, $00, $00, $00
	db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
	db $01, $01, $ff, $01, $01, $ff, $ff, $ff, $00, $00, $00, $00, $00, $00, $00, $00
	db $f0, $f0, $f0, $b0, $f0, $b0, $f0, $f0, $00, $00, $00, $00, $07, $07, $18, $1f
	db $20, $3f, $30, $3f, $18, $17, $3f, $2c, $7b, $4f, $70, $5f, $90, $9f, $90, $9f
	db $70, $7f, $11, $1f, $3e, $3e, $3e, $3e, $00, $00, $7c, $7c, $66, $66, $66, $66
	db $7c, $7c, $68, $68, $66, $66, $00, $00, $00, $00, $3c, $3c, $66, $66, $66, $66
	db $66, $66, $66, $66, $3c, $3c, $00, $00, $00, $00, $60, $60, $60, $60, $60, $60
	db $60, $60, $60, $60, $7e, $7e, $00, $00, $00, $00, $3c, $3c, $66, $66, $60, $60
	db $6e, $6e, $66, $66, $3e, $3e, $00, $00, $00, $ee, $00, $00, $ff, $ff, $ff, $ff
	db $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff, $00, $01, $00, $02, $00, $02, $00, $04
	db $00, $08, $00, $08, $00, $10, $00, $10, $80, $80, $c0, $40, $c0, $40, $e0, $20
	db $30, $50, $30, $50, $38, $48, $18, $28, $00, $00, $00, $00, $00, $00, $00, $00
	db $00, $03, $00, $03, $00, $02, $00, $02, $00, $00, $00, $00, $00, $00, $00, $00
	db $08, $f8, $08, $18, $08, $a8, $08, $48, $00, $80, $00, $80, $00, $80, $00, $80
	db $00, $00, $00, $00, $00, $00, $00, $00, $00, $20, $00, $20, $00, $20, $1f, $20
	db $00, $40, $00, $40, $00, $40, $00, $40, $1c, $24, $0c, $34, $0c, $34, $04, $fc
	db $0e, $32, $0e, $32, $0e, $32, $0e, $32, $00, $00, $00, $00, $00, $00, $00, $00
	db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
	db $00, $1f, $00, $18, $00, $15, $00, $12, $00, $00, $00, $00, $00, $00, $00, $00
	db $40, $c0, $40, $c0, $40, $40, $40, $40, $00, $02, $00, $03, $00, $02, $00, $02
	db $00, $02, $00, $03, $00, $02, $00, $02, $08, $af, $08, $1a, $08, $ad, $08, $4f
	db $08, $a8, $08, $18, $08, $a8, $08, $48, $00, $00, $00, $00, $00, $00, $00, $00
	db $00, $00, $00, $00, $00, $01, $00, $02, $00, $40, $15, $40, $15, $40, $15, $40
	db $15, $c0, $15, $c1, $17, $43, $16, $46, $24, $0c, $34, $0c, $34, $04, $fc, $0e
	db $32, $0e, $32, $0e, $32, $0e, $32, $00, $00, $00, $00, $00, $00, $00, $00, $00
	db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $2a, $20, $01
	db $00, $1d, $01, $09, $00, $07, $01, $0b, $00, $03, $20, $04, $00, $20, $20, $06
	db $00, $0a, $80, $17, $00, $06, $01, $06, $00, $04, $01, $05, $00, $1e, $80, $0b
	db $00, $06, $80, $1c, $00, $0a, $10, $08, $11, $04, $01, $02, $00, $04, $01, $06
	db $00, $00, $10, $06, $00, $04, $10, $05, $00, $1a, $80, $24, $00, $15, $01, $07
	db $00, $20, $10, $04, $00, $05, $10, $03, $00, $0d, $10, $06, $00, $03, $10, $05
	db $00, $25, $80, $15, $00, $1b, $10, $04, $00, $13, $80, $03, $00, $1c, $80, $19
	db $00, $1a, $01, $06, $00, $0a, $20, $01, $00, $09, $20, $02, $00, $14, $10, $03
	db $00, $0e, $80, $16, $00, $0a, $10, $0a, $11, $06, $10, $16, $00, $13, $80, $25
	db $00, $1c, $01, $06, $00, $03, $20, $02, $00, $0e, $20, $03, $00, $04, $20, $02
	db $00, $03, $20, $05, $00, $0d, $80, $21, $00, $13, $01, $07, $00, $05, $01, $06
	db $00, $04, $01, $05, $00, $06, $20, $03, $00, $05, $20, $02, $00, $1c, $20, $03
	db $00, $0e, $80, $12, $00, $0c, $10, $04, $00, $02, $01, $08, $00, $10, $01, $08
	db $00, $1e, $80, $19, $00, $10, $10, $03, $00, $04, $10, $05, $00, $24, $80, $1c
	db $00, $05, $01, $05, $00, $11, $20, $03, $00, $12, $80, $20, $00, $0a, $10, $01
	db $11, $06, $01, $00, $00, $04, $10, $04, $00, $04, $10, $03, $00, $02, $10, $19
	db $00, $04, $10, $07, $00, $0a, $00, $00, $00, $00, $00, $00, $00, $4d, $20, $08
	db $21, $06, $20, $0b, $00, $07, $20, $06, $00, $64, $10, $00, $11, $06, $10, $05
	db $00, $2f, $80, $16, $00, $17, $20, $05, $00, $06, $20, $06, $00, $10, $80, $18
	db $00, $34, $01, $05, $00, $01, $10, $0e, $11, $06, $10, $20, $00, $0a, $80, $0a
	db $00, $2b, $20, $06, $00, $06, $20, $05, $00, $05, $20, $06, $00, $0a, $80, $0c
	db $00, $0a, $01, $07, $00, $02, $10, $0b, $00, $05, $10, $04, $00, $0d, $80, $1c
	db $00, $75, $01, $06, $00, $0e, $80, $1f, $00, $1a, $01, $06, $00, $00, $10, $07
	db $00, $05, $10, $06, $00, $04, $10, $08, $00, $03, $10, $08, $00, $0c, $80, $0f
	db $00, $0a, $01, $07, $00, $00, $10, $3d, $00, $05, $80, $1f, $00, $00, $00, $00
	db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
	db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $10, $18, $00, $04
	db $08, $00, $04, $08, $08, $00, $04, $14, $10, $08, $10, $10, $14, $18, $14, $00
	db $0c, $04, $18, $00, $14, $14, $08, $04, $04, $0c, $00, $18, $04, $00, $08, $0c
	db $0c, $18, $00, $0c, $08, $00, $18, $10, $14, $14, $18, $08

; Start routine of each square channel sound effect (1-8)
SFXStartHandlers::
	dw StartSFX1
	dw StartSFX2
	dw StartSFX3
	dw StartSFX4
	dw StartSFX5
	dw StartSFX6
	dw StartSFX7
	dw StartSFX8

; Per-frame routine of each square channel sound effect (1-8)
SFXUpdateHandlers::
	dw UpdateSFX1
	dw UpdateSFXOneNote
	dw UpdateSFX3
	dw UpdateSFXOneNote
	dw UpdateSFXOneNote
	dw UpdateSFX6
	dw UpdateSFX7
	dw UpdateSFX8

; Start routine of each noise sound effect (1-4)
NoiseStartHandlers::
	dw StartNoise1
	dw StartNoise2
	dw StartNoise3
	dw StartNoise4

; Per-frame routine of each noise sound effect (1-4)
NoiseUpdateHandlers::
	dw UpdateNoiseOneShot
	dw UpdateNoiseOneShot
	dw UpdateNoiseOneShot
	dw UpdateNoise4

; Pointers to the 17 song headers
SongTable::
	dw Song01Header
	dw Song02Header
	dw Song03Header
	dw Song04Header
	dw Song05Header
	dw Song06Header
	dw Song07Header
	dw Song08Header
	dw Song09Header
	dw Song0AHeader
	dw Song0BHeader
	dw Song0CHeader
	dw Song0DHeader
	dw Song0EHeader
	dw Song0FHeader
	dw Song10Header
	dw Song11Header

;@ def SoundNothing()
;@ path: sound/api
;@ Empty routine; SoundEngine calls it every frame (a leftover hook).
;@ sig: 30ba9599
SoundNothing::
;> pass
	ret


;@ def SoundEngine()
;@ path: sound/api
;@ The sound engine, once per frame (UpdateSound). Handles pausing (silence
;@ plus a short jingle), then sound effects of the three effect slots, a
;@ requested song, the music itself and the stereo panning. Requests are
;@ cleared afterwards; demos play no sound at all.
;@ reads: wSoundPause, wPauseTimer, hDemo
;@ writes: wSFXRequest, wMusicRequest, wWaveSFXRequest, wNoiseSFXRequest, wSoundPause, wSFXPlaying, wWaveSFXPlaying, wNoiseSFXPlaying, wPauseTimer, wChannel1, wChannel2, wChannel3, wChannel4
;@ test: play('music', rand(1, 0x11), rand(0, 120))
;@ test: wSoundPause = rng.choice([0, 0, 1, 2])
;@ test: wPauseTimer = rng.choice([0, 0, 0x29, 0x21, 0x19, 0x11, 0x10])
;@ test: hDemo = rng.choice([0, 0, 1])
;@ test: mem[0xDFE0] = rng.choice([0, 0, rand(1, 8)]); mem[0xDFF8] = rng.choice([0, 0, rand(1, 4)])
;@ sig: 342bcb17
SoundEngine::
;>@regs # (af, bc, de and hl are saved here and restored before returning)
	push af
	push bc
	push de
	push hl
;> if wSoundPause == 1:                             # pause
	ld a, [wSoundPause]
	cp $01
	jr z, .pause

;>@silence     SilenceChannels()
;>@sfx0     wSFXPlaying = 0
;>@wave0     wWaveSFXPlaying = 0
;>@noise0     wNoiseSFXPlaying = 0
;>@ch3     wChannel3[0x0F] &= 0x7F
;>@ch1     wChannel1[0x0F] &= 0x7F
;>@ch2     wChannel2[0x0F] &= 0x7F
;>@ch4     wChannel4[0x0F] &= 0x7F
;>@wave     LoadWaveRAM(PauseWave)
;>@timer     wPauseTimer = 0x30                           # the pause jingle
;>@noteA     WriteSquare2Regs(PauseNoteA)
;> elif wSoundPause == 2 or not wPauseTimer:
	cp $02
	jr z, .resume

	ld a, [wPauseTimer]
	and a
	jr nz, .paused

;>@resume     if wSoundPause == 2: wPauseTimer = 0         # resume
;>     if hDemo:                                    # demos are silent
.run
	ldh a, [hDemo]
	and a
	jr z, .update

;>         wSFXRequest = 0
	xor a
	ld [wSFXRequest], a
;>         wMusicRequest = 0
	ld [wMusicRequest], a
;>         wWaveSFXRequest = 0
	ld [wWaveSFXRequest], a
;>         wNoiseSFXRequest = 0
	ld [wNoiseSFXRequest], a

;>     SoundNothing()
.update
	call SoundNothing
;>     UpdateSquareSFX()
	call UpdateSquareSFX
;>     UpdateNoiseSFX()
	call UpdateNoiseSFX
;>     UpdateWaveSFX()
	call UpdateWaveSFX
;>     StartRequestedSong()
	call StartRequestedSong
;>     UpdateMusic()
	call UpdateMusic
;>     UpdatePanning()
	call UpdatePanning

;>@else else:                                            # paused: play the jingle, nothing else
;>@dec     wPauseTimer -= 1
;>@is28     if wPauseTimer == 0x28:
;>@b28         WriteSquare2Regs(PauseNoteB)
;>@is20     elif wPauseTimer == 0x20:
;>@a20         WriteSquare2Regs(PauseNoteA)             # (the same code as above)
;>@is18     elif wPauseTimer == 0x18:
;>@b18         WriteSquare2Regs(PauseNoteB)             # (the same code as above)
;>@is10     elif wPauseTimer == 0x10:
;>@hold         wPauseTimer += 1                         # stays here until resumed
;> wSFXRequest = 0
.done
	xor a
	ld [wSFXRequest], a
;> wMusicRequest = 0
	ld [wMusicRequest], a
;> wWaveSFXRequest = 0
	ld [wWaveSFXRequest], a
;> wNoiseSFXRequest = 0
	ld [wNoiseSFXRequest], a
;> wSoundPause = 0
	ld [wSoundPause], a
;=@regs
	pop hl
	pop de
	pop bc
	pop af
;> return
	ret

;=@silence
.pause
	call SilenceChannels
;=@sfx0
	xor a
	ld [wSFXPlaying], a
;=@wave0
	ld [wWaveSFXPlaying], a
;=@noise0
	ld [wNoiseSFXPlaying], a
;=@ch3
	ld hl, wChannel3 + $0F
	res 7, [hl]
;=@ch1
	ld hl, wChannel1 + $0F
	res 7, [hl]
;=@ch2
	ld hl, wChannel2 + $0F
	res 7, [hl]
;=@ch4
	ld hl, wChannel4 + $0F
	res 7, [hl]
;=@wave
	ld hl, PauseWave
	call LoadWaveRAM
;=@timer
	ld a, $30
	ld [wPauseTimer], a

;=@noteA
.noteA
	ld hl, PauseNoteA

.note
	call WriteSquare2Regs
	jr .done

;=@b28
.noteB
	ld hl, PauseNoteB
	jr .note

;=@resume
.resume
	xor a
	ld [wPauseTimer], a
	jr .run

;=@dec
.paused
	ld hl, wPauseTimer
	dec [hl]
;=@is28
	ld a, [hl]
	cp $28
	jr z, .noteB

;=@is20
	cp $20
	jr z, .noteA

;=@is18
	cp $18
	jr z, .noteB

;=@is10
	cp $10
	jr nz, .done

;=@hold
	inc [hl]
	jr .done

; NR21-NR24 values of the two pause jingle notes

PauseNoteA::
	db $b2, $e3, $83, $c7

PauseNoteB::
	db $b2, $e3, $c1, $c7

;@ def IsWaveSFX1Playing() -> zero
;@ path: sound/sfx/wave
;@ Returns whether wave effect 1 is playing (in the zero flag).
;@ reads: wWaveSFXPlaying
;@ test: wWaveSFXPlaying = rand(0, 2)
;@ sig: 4a515e71
IsWaveSFX1Playing::
;> return wWaveSFXPlaying == 1
	ld a, [wWaveSFXPlaying]
	cp $01
	ret

;@ def IsSFX5Playing() -> zero
;@ path: sound/sfx/square
;@ Returns whether square effect 5 (garbage) is playing.
;@ reads: wSFXPlaying
;@ test: wSFXPlaying = rand(0, 8)
;@ sig: 4edd0cf7
IsSFX5Playing::
;> return wSFXPlaying == 5
	ld a, [wSFXPlaying]
	cp $05
	ret

;@ def IsSFX7Playing() -> zero
;@ path: sound/sfx/square
;@ Returns whether square effect 7 (tetris) is playing.
;@ reads: wSFXPlaying
;@ test: wSFXPlaying = rand(0, 8)
;@ sig: 7ceb6e75
IsSFX7Playing::
;> return wSFXPlaying == 7
	ld a, [wSFXPlaying]
	cp $07
	ret

;@ def IsSFX8Playing() -> zero
;@ path: sound/sfx/square
;@ Returns whether square effect 8 (level up) is playing.
;@ reads: wSFXPlaying
;@ test: wSFXPlaying = rand(0, 8)
;@ sig: fb7372ba
IsSFX8Playing::
;> return wSFXPlaying == 8
	ld a, [wSFXPlaying]
	cp $08
	ret

; NR10-NR14 values: effect 1 (menu cursor, 2 steps) and effect 2 (confirm)

SFX1Regs::
	db $00, $b5, $d0, $40, $c7, $00, $b5, $20, $40, $c7

SFX2Regs::
	db $00, $b6, $a1, $80, $c7

;@ def StartSFX1(slot: de)
;@ path: sound/sfx/square
;@ Square effect 1, menu cursor: 2 steps of 5 frames.
;@ reads: wSndTemp
;@ test: slot = 0xDFE2
;@ sig: ef1816b2
StartSFX1::
;> StartSFX(5, SFX1Regs, slot)
	ld a, $05
	ld hl, SFX1Regs
	jp StartSFX

;@ def UpdateSFX1(slot: de)
;@ path: sound/sfx/square
;@ Every 5 frames: the second note, then stop.
;@ test: slot = 0xDFE2
;@ test: mem[0xDFE3] = 5; mem[0xDFE2] = rand(0, 4); mem[0xDFE4] = rand(0, 1)
;@ sig: bbd5e7e8
UpdateSFX1::
;> if SFXTick(slot): return
	call SFXTick
	and a
	ret nz

;> mem[addr(wSFXPlaying) + 3] += 1                               # step
	ld hl, wSFXPlaying + 3
	inc [hl]
;> if mem[addr(wSFXPlaying) + 3] == 2:
;>     StopSquareSFX()                              # (jumps straight to it)
	ld a, [hl]
	cp $02
	jr z, StopSquareSFX

;> else:
;>     WriteSquare1Regs(SFX1Regs + 5)
	ld hl, SFX1Regs + 5
	jp WriteSquare1Regs

;@ def StartSFX2(slot: de)
;@ path: sound/sfx/square
;@ Square effect 2, confirm / tally / typing: one note, 3 frames.
;@ reads: wSndTemp
;@ test: slot = 0xDFE2
;@ sig: 92d9256f
StartSFX2::
;> StartSFX(3, SFX2Regs, slot)
	ld a, $03
	ld hl, SFX2Regs
	jp StartSFX

;@ def UpdateSFXOneNote(slot: de)
;@ path: sound/sfx/square
;@ Shared by effects 2, 4 and 5: when the period is over, stop.
;@ test: slot = 0xDFE2
;@ test: mem[0xDFE3] = rand(1, 8); mem[0xDFE2] = rand(0, mem[0xDFE3] - 1)
;@ sig: d0dbf27c
UpdateSFXOneNote::
;> if SFXTick(slot): return
;> StopSquareSFX()                                  # falls through
	call SFXTick
	and a
	ret nz

;@ def StopSquareSFX()
;@ path: sound/sfx/square
;@ Ends the square channel effect and gives channel 1 back to the music.
;@ writes: wSFXPlaying, rNR10, rNR12, rNR14, wChannel1
;@ sig: 5f001df6
StopSquareSFX::
;> wSFXPlaying = 0
	xor a
	ld [wSFXPlaying], a
;> rNR10 = 0                                       # silence channel 1
	ldh [rNR10], a
;> rNR12 = 0x08
	ld a, $08
	ldh [rNR12], a
;> rNR14 = 0x80
	ld a, $80
	ldh [rNR14], a
;> wChannel1[0x0F] &= 0x7F
	ld hl, wChannel1 + $0F
	res 7, [hl]
;> return
	ret

; NR10-NR14 values of effect 7 (tetris): two notes alternating

SFX7Regs::
	db $00, $80, $e1, $c1, $87, $00, $80, $e1, $ac, $87

;@ def StartSFX7(period: a, slot: de)
;@ path: sound/sfx/square
;@ Square effect 7, tetris. (The period is whatever a holds: the high byte
;@ of this routine's address, left by TableLookup - UpdateSFX7 ignores it.)
;@ reads: wSndTemp
;@ test: period = 0x65
;@ test: slot = 0xDFE2
;@ sig: c5a50b5e
StartSFX7::
;> StartSFX(period, SFX7Regs, slot)
	ld hl, SFX7Regs
	jp StartSFX

;@ def UpdateSFX7(slot: de)
;@ path: sound/sfx/square
;@ Every frame: the note changes at steps 4, 11 and 15; at step 24 the
;@ effect hands over to wave effect 1.
;@ writes: wWaveSFXRequest
;@ test: slot = 0xDFE2
;@ test: mem[0xDFE4] = rng.choice([3, 10, 14, 23, 5])
;@ sig: 957782f8
UpdateSFX7::
;> mem[addr(wSFXPlaying) + 3] += 1
	ld hl, wSFXPlaying + 3
	inc [hl]
;> step = mem[addr(wSFXPlaying) + 3]
	ld a, [hl]
;> if step == 4:
	cp $04
	jr z, .noteB

;>@b4     WriteSquare1Regs(SFX7Regs + 5)
;> elif step == 11:
	cp $0b
	jr z, .noteA

;>@a11     WriteSquare1Regs(SFX7Regs)
;> elif step == 15:
	cp $0f
	jr z, .noteB

;>@b15     WriteSquare1Regs(SFX7Regs + 5)               # (the same code as above)
;> elif step == 24:
	cp $18
	jp z, .handOver

;>@req     wWaveSFXRequest = 1
;>@stop     StopSquareSFX()
;> else:
;>     return
	ret

;=@req
.handOver
	ld a, $01
	ld hl, wWaveSFXRequest
	ld [hl], a
;=@stop
	jp StopSquareSFX

;=@b4
.noteB
	ld hl, SFX7Regs + 5
	jp WriteSquare1Regs

;=@a11
.noteA
	ld hl, SFX7Regs
	jp WriteSquare1Regs

; NR10-NR14 values of effect 4 (move)

SFX4Regs::
	db $48, $bc, $42, $66, $87

;@ def StartSFX4(slot: de)
;@ path: sound/sfx/square
;@ Square effect 4, move left/right - unless a more important effect plays.
;@ reads: wWaveSFXPlaying, wSFXPlaying, wSndTemp
;@ test: slot = 0xDFE2
;@ test: wWaveSFXPlaying = rand(0, 2)
;@ test: wSFXPlaying = rand(0, 8)
;@ sig: 9ddc1dcc
StartSFX4::
;> if IsWaveSFX1Playing(): return
	call IsWaveSFX1Playing
	ret z

;> if IsSFX8Playing(): return
	call IsSFX8Playing
	ret z

;> if IsSFX7Playing(): return
	call IsSFX7Playing
	ret z

;> if IsSFX5Playing(): return
	call IsSFX5Playing
	ret z

;> StartSFX(2, SFX4Regs, slot)
	ld a, $02
	ld hl, SFX4Regs
	jp StartSFX

; NR10-NR14 values of effect 8 (level up): four notes

SFX8Regs::
	db $00, $b0, $f1, $b6, $c7, $00, $b0, $f1, $c4, $c7, $00, $b0, $f1, $ce, $c7
	db $00, $b0, $f1, $db, $c7

;@ def StartSFX8(slot: de)
;@ path: sound/sfx/square
;@ Square effect 8, level up - unless the tetris effect plays.
;@ reads: wSFXPlaying, wSndTemp
;@ test: slot = 0xDFE2
;@ test: wSFXPlaying = rand(0, 8)
;@ sig: 942389f8
StartSFX8::
;> if IsSFX7Playing(): return
	call IsSFX7Playing
	ret z

;> StartSFX(7, SFX8Regs, slot)
	ld a, $07
	ld hl, SFX8Regs
	jp StartSFX

;@ def UpdateSFX8(slot: de)
;@ path: sound/sfx/square
;@ Every 7 frames the next of the four notes; then stop.
;@ test: slot = 0xDFE2
;@ test: mem[0xDFE3] = 7; mem[0xDFE2] = rng.choice([6, 2]); mem[0xDFE4] = rand(0, 5)
;@ sig: 8da16e16
UpdateSFX8::
;> if SFXTick(slot): return
	call SFXTick
	and a
	ret nz

;> mem[addr(wSFXPlaying) + 3] += 1
	ld hl, wSFXPlaying + 3
	inc [hl]
;> step = mem[addr(wSFXPlaying) + 3]
	ld a, [hl]
;> if step == 1:
	cp $01
	jr z, .note1

;>@r1     regs = SFX8Regs + 5
;> elif step == 2:
	cp $02
	jr z, .note2

;>@r2     regs = SFX8Regs + 10
;> elif step == 3:
	cp $03
	jr z, .note3

;>@r3     regs = SFX8Regs + 15
;> elif step == 4:
	cp $04
	jr z, .note4

;>@r4     regs = SFX8Regs
;> elif step == 5:
;>     StopSquareSFX()                              # (jumps straight to it)
;>     return
	cp $05
	jp z, StopSquareSFX

;> else:
;>     return
	ret

;=@r1
.note1
	ld hl, SFX8Regs + 5
	jr .write

;=@r2
.note2
	ld hl, SFX8Regs + 10
	jr .write

;=@r3
.note3
	ld hl, SFX8Regs + 15
	jr .write

;=@r4
.note4
	ld hl, SFX8Regs

;>@write WriteSquare1Regs(regs)
.write
	jp WriteSquare1Regs

; Effect 6 (line clear): first notes' registers, then per step an envelope
; (0-terminated) and a frequency low byte

SFX6Regs::
	db $3e, $80, $e3, $00, $c4

SFX6Envelopes::
	db $93, $83, $83, $73, $63, $53, $43, $33, $23, $13, $00

SFX6Frequencies::
	db $00, $23, $43, $63, $83, $a3, $c3, $d3, $e3, $ff

;@ def StartSFX6(slot: de)
;@ path: sound/sfx/square
;@ Square effect 6, line clear - unless a more important effect plays.
;@ reads: wWaveSFXPlaying, wSFXPlaying, wSndTemp
;@ test: slot = 0xDFE2
;@ test: wWaveSFXPlaying = rand(0, 2)
;@ test: wSFXPlaying = rand(0, 8)
;@ sig: d984d161
StartSFX6::
;> if IsWaveSFX1Playing(): return
	call IsWaveSFX1Playing
	ret z

;> if IsSFX8Playing(): return
	call IsSFX8Playing
	ret z

;> if IsSFX7Playing(): return
	call IsSFX7Playing
	ret z

;> StartSFX(6, SFX6Regs, slot)
	ld a, $06
	ld hl, SFX6Regs
	jp StartSFX

;@ def UpdateSFX6(slot: de)
;@ path: sound/sfx/square
;@ Every 6 frames the next envelope/frequency pair - a rising, fading sweep.
;@ test: slot = 0xDFE2
;@ test: mem[0xDFE3] = 6; mem[0xDFE2] = rng.choice([5, 1]); mem[0xDFE4] = rand(0, 10)
;@ sig: 5b23d1f8
UpdateSFX6::
;> if SFXTick(slot): return
	call SFXTick
	and a
	ret nz

;> step = mem[addr(wSFXPlaying) + 3]
	ld hl, wSFXPlaying + 3
	ld c, [hl]
;> mem[addr(wSFXPlaying) + 3] = step + 1
	inc [hl]
;> envelope = mem[SFX6Envelopes + step]
	ld b, $00
	ld hl, SFX6Envelopes
	add hl, bc
	ld a, [hl]
;> if envelope == 0:
;>     return StopSquareSFX()                       # (jumps straight to it)
	and a
	jp z, StopSquareSFX

;> freq_lo = mem[SFX6Frequencies + step]
	ld e, a
	ld hl, SFX6Frequencies
	add hl, bc
	ld a, [hl]
;> SetSquare1Note(envelope, freq_lo, 0x86)          # (falls through into it)
	ld d, a
	ld b, $86

;@ def SetSquare1Note(envelope: e, freq_lo: d, freq_hi: b)
;@ path: sound/sfx/square
;@ Writes NR12, NR13 and NR14 (trigger in freq_hi).
;@ test: skip shared tail, entered with registers set by its callers
;@ sig: 0860096d
SetSquare1Note::
;> rNR12 = envelope
	ld c, LOW(rNR12)
	ld a, e
	ldh [c], a
;> rNR13 = freq_lo
	inc c
	ld a, d
	ldh [c], a
;> rNR14 = freq_hi
	inc c
	ld a, b
	ldh [c], a
;> return
	ret

; Effect 3 (rotate): first note's registers, envelopes (0-terminated), frequency low bytes

SFX3Regs::
	db $3b, $80, $b2, $87, $87

SFX3Envelopes::
	db $a2, $93, $62, $43, $23, $00

SFX3Frequencies::
	db $80, $40, $80, $40, $80

;@ def StartSFX3(slot: de)
;@ path: sound/sfx/square
;@ Square effect 3, rotate - unless a more important effect plays.
;@ reads: wWaveSFXPlaying, wSFXPlaying, wSndTemp
;@ test: slot = 0xDFE2
;@ test: wWaveSFXPlaying = rand(0, 2)
;@ test: wSFXPlaying = rand(0, 8)
;@ sig: 50ee6972
StartSFX3::
;> if IsWaveSFX1Playing(): return
	call IsWaveSFX1Playing
	ret z

;> if IsSFX8Playing(): return
	call IsSFX8Playing
	ret z

;> if IsSFX7Playing(): return
	call IsSFX7Playing
	ret z

;> if IsSFX5Playing(): return
	call IsSFX5Playing
	ret z

;> StartSFX(3, SFX3Regs, slot)
	ld a, $03
	ld hl, SFX3Regs
	jp StartSFX

;@ def UpdateSFX3(slot: de)
;@ path: sound/sfx/square
;@ Every 3 frames the next envelope/frequency pair.
;@ test: slot = 0xDFE2
;@ test: mem[0xDFE3] = 3; mem[0xDFE2] = rng.choice([2, 0]); mem[0xDFE4] = rand(0, 5)
;@ sig: da0985f0
UpdateSFX3::
;> if SFXTick(slot): return
	call SFXTick
	and a
	ret nz

;> step = mem[addr(wSFXPlaying) + 3]
	ld hl, wSFXPlaying + 3
	ld c, [hl]
;> mem[addr(wSFXPlaying) + 3] = step + 1
	inc [hl]
;> envelope = mem[SFX3Envelopes + step]
	ld b, $00
	ld hl, SFX3Envelopes
	add hl, bc
	ld a, [hl]
;> if envelope == 0:
;>     return StopSquareSFX()                       # (jumps straight to it)
	and a
	jp z, StopSquareSFX

;> freq_lo = mem[SFX3Frequencies + step]
	ld e, a
	ld hl, SFX3Frequencies
	add hl, bc
	ld a, [hl]
;> SetSquare1Note(envelope, freq_lo, 0x87)
	ld d, a
	ld b, $87
	jr SetSquare1Note

;@ def StartSFX5(slot: de)
;@ path: sound/sfx/square
;@ Square effect 5, garbage rising (2-player) - unless the tetris effect plays.
;@ reads: wSFXPlaying, wSndTemp
;@ test: slot = 0xDFE2
;@ test: wSFXPlaying = rand(0, 8)
;@ sig: 156aa7e8
StartSFX5::
;> if IsSFX7Playing(): return
	call IsSFX7Playing
	ret z

;> StartSFX(0x28, SFX5Regs, slot)
	ld a, $28
	ld hl, SFX5Regs
	jp StartSFX

; NR10-NR14 of effect 5, then NR41-NR44 of the noise effects 2, 1, 3, 4,
; then noise effect 4's NR43 and NR42 values per step

SFX5Regs::
	db $b7, $80, $90, $ff, $83

Noise2Regs::
	db $00, $d1, $45, $80

Noise1Regs::
	db $00, $f1, $54, $80

Noise3Regs::
	db $00, $d5, $65, $80

Noise4Regs::
	db $00, $70, $66, $80

Noise4Frequencies::
	db $65, $65, $65, $64, $57, $56, $55, $54, $54, $54, $54, $54, $47, $46, $46, $45
	db $45, $45, $44, $44, $44, $34, $34, $34, $34, $34, $34, $34, $34, $34, $34, $34
	db $34, $34, $34, $34

Noise4Envelopes::
	db $70, $60, $70, $70, $70, $80, $90, $a0, $d0, $f0, $e0, $d0, $c0, $b0, $a0, $90
	db $80, $70, $60, $50, $40, $30, $30, $20, $20, $20, $20, $20, $20, $20, $20, $20
	db $20, $20, $10, $10

;@ def StartNoise3(slot: de)
;@ path: sound/sfx/noise
;@ Noise effect 3, smoke puff.
;@ reads: wSndTemp
;@ test: slot = 0xDFFA
;@ sig: b9ffde35
StartNoise3::
;> StartSFX(0x30, Noise3Regs, slot)
	ld a, $30
	ld hl, Noise3Regs
	jp StartSFX

;@ def StartNoise4(slot: de)
;@ path: sound/sfx/noise
;@ Noise effect 4, rocket engine.
;@ reads: wSndTemp
;@ test: slot = 0xDFFA
;@ sig: 1cefa4b6
StartNoise4::
;> StartSFX(0x30, Noise4Regs, slot)
	ld a, $30
	ld hl, Noise4Regs
	jp StartSFX

;@ def UpdateNoise4(slot: de)
;@ path: sound/sfx/noise
;@ Every $30 frames the rocket noise moves on (36 steps of pitch and volume).
;@ test: slot = 0xDFFA
;@ test: mem[0xDFFB] = 0x30; mem[0xDFFA] = rng.choice([0x2F, 3]); mem[0xDFFC] = rand(0, 0x24)
;@ sig: 8401feb6
UpdateNoise4::
;> if SFXTick(slot): return
	call SFXTick
	and a
	ret nz

;> step = mem[addr(wNoiseSFXPlaying) + 3]
	ld hl, wNoiseSFXPlaying + 3
	ld a, [hl]
	ld c, a
;> if step == 0x24:
;>     return StopNoiseSFX()                        # (jumps straight to it)
	cp $24
	jp z, StopNoiseSFX

;> mem[addr(wNoiseSFXPlaying) + 3] = step + 1
	inc [hl]
;> rNR43 = mem[Noise4Frequencies + step]
	ld b, $00
	push bc
	ld hl, Noise4Frequencies
	add hl, bc
	ld a, [hl]
	ldh [rNR43], a
;> rNR42 = mem[Noise4Envelopes + step]
	pop bc
	ld hl, Noise4Envelopes
	add hl, bc
	ld a, [hl]
	ldh [rNR42], a
;> rNR44 = 0x80
	ld a, $80
	ldh [rNR44], a
;> return
	ret

;@ def StartNoise1(slot: de)
;@ path: sound/sfx/noise
;@ Noise effect 1, rows falling into place.
;@ reads: wSndTemp
;@ test: slot = 0xDFFA
;@ sig: 2ba1e43b
StartNoise1::
;> StartSFX(0x20, Noise1Regs, slot)
	ld a, $20
	ld hl, Noise1Regs
	jp StartSFX

;@ def StartNoise2(slot: de)
;@ path: sound/sfx/noise
;@ Noise effect 2, piece locks.
;@ reads: wSndTemp
;@ test: slot = 0xDFFA
;@ sig: d1adbd41
StartNoise2::
;> StartSFX(0x12, Noise2Regs, slot)
	ld a, $12
	ld hl, Noise2Regs
	jp StartSFX

;@ def UpdateNoiseOneShot(slot: de)
;@ path: sound/sfx/noise
;@ Shared by noise effects 1-3: when the period is over, stop.
;@ test: slot = 0xDFFA
;@ test: mem[0xDFFB] = rand(1, 0x30); mem[0xDFFA] = rand(0, mem[0xDFFB] - 1)
;@ sig: d0dbf27c
UpdateNoiseOneShot::
;> if SFXTick(slot): return
;> StopNoiseSFX()                                   # falls through
	call SFXTick
	and a
	ret nz

;@ def StopNoiseSFX()
;@ path: sound/sfx/noise
;@ Ends the noise effect and gives channel 4 back to the music.
;@ writes: wNoiseSFXPlaying, rNR42, rNR44, wChannel4
;@ sig: d7df54db
StopNoiseSFX::
;> wNoiseSFXPlaying = 0
	xor a
	ld [wNoiseSFXPlaying], a
;> rNR42 = 0x08
	ld a, $08
	ldh [rNR42], a
;> rNR44 = 0x80
	ld a, $80
	ldh [rNR44], a
;> wChannel4[0x0F] &= 0x7F
	ld hl, wChannel4 + $0F
	res 7, [hl]
;> return
	ret

; NR30-NR34 values of wave effect 2 (game over)
WaveSFX2Regs::
	db $80, $3a, $20, $60, $c6

;@ def StartWaveSFX2(id: a)
;@ path: sound/sfx/wave
;@ Wave effect 2, game over: wave RAM gets Waveform4 and the pitch's high
;@ nibble starts at a random point between $D0 and $EF.
;@ writes: wWaveSFXSlot
;@ test: id = 2
;@ sig: 6f6f1ca6
StartWaveSFX2::
;> StartWaveSFX(id, Waveform4)
	ld hl, Waveform4
	call StartWaveSFX
;> pitch = 0xD0 + (rDIV & 0x1F)
	ldh a, [rDIV]
	and $1f
	ld b, a
	ld a, $d0
	add b
;> mem[addr(wWaveSFXPlaying) + 4] = pitch
	ld [wWaveSFXPlaying + 4], a
;> WriteWaveRegs(WaveSFX2Regs)
	ld hl, WaveSFX2Regs
	jp WriteWaveRegs


;@ def UpdateWaveSFX2()
;@ path: sound/sfx/wave
;@ Every frame: the pitch climbs by 2 for 14 frames, then falls by 3 until
;@ frame 30 ends the effect. The low nibble of NR33 is random each frame,
;@ which makes it rumble.
;@ test: mem[0xDFF4] = rng.choice([0x0C, 0x0D, 0x1D, rand(0, 0x1D)])
;@ sig: 85c377af
UpdateWaveSFX2::
;> jitter = rDIV & 0x0F
	ldh a, [rDIV]
	and $0f
	ld b, a
;> step = mem[addr(wWaveSFXPlaying) + 3] = u8(mem[addr(wWaveSFXPlaying) + 3] + 1)
	ld hl, wWaveSFXPlaying + 3
	inc [hl]
	ld a, [hl]
;> if step < 0x0E:
	ld hl, wWaveSFXPlaying + 4
	cp $0e
	jr nc, .falling

;>     mem[addr(wWaveSFXPlaying) + 4] = u8(mem[addr(wWaveSFXPlaying) + 4] + 2)
	inc [hl]
	inc [hl]

;>@stop elif step == 0x1E: return StopWaveSFX()
;>@fall else: mem[addr(wWaveSFXPlaying) + 4] = u8(mem[addr(wWaveSFXPlaying) + 4] - 3)
;> rNR33 = (mem[addr(wWaveSFXPlaying) + 4] & 0xF0) | jitter
.write
	ld a, [hl]
	and $f0
	or b
	ld c, LOW(rNR33)
	ldh [c], a
	ret

;=@stop
.falling
	cp $1e
	jp z, StopWaveSFX

;=@fall
	dec [hl]
	dec [hl]
	dec [hl]
	jr .write

;@ def UpdateWaveSFX()
;@ path: sound/sfx/wave
;@ The wave channel part of the sound engine: start the requested wave
;@ effect, or advance the one playing.
;@ reads: wWaveSFXPlaying, wWaveSFXRequest
;@ test: wWaveSFXRequest = rng.choice([0, 0, 1, 2, 3])
;@ test: wWaveSFXPlaying = rand(0, 3)
;@ test: mem[0xDFF4] = rand(0, 0x1D)
;@ test: mem[0xDFF5] = rand(0, 3)
;@ sig: 98257835
UpdateWaveSFX::
;> if wWaveSFXRequest == 1: return StartWaveSFX1(1)
	ld a, [wWaveSFXRequest]
	cp $01
	jp z, StartWaveSFX1

;> if wWaveSFXRequest == 2: return StartWaveSFX2(2)
	cp $02
	jp z, StartWaveSFX2

;> if wWaveSFXPlaying == 1: return UpdateWaveSFX1()
	ld a, [wWaveSFXPlaying]
	cp $01
	jp z, UpdateWaveSFX1

;> if wWaveSFXPlaying == 2: return UpdateWaveSFX2()
	cp $02
	jp z, UpdateWaveSFX2

;> return
	ret
WaveSFX1Regs::
	db $80, $80, $20, $9d, $87, $80, $f8, $20, $98, $87, $80, $fb, $20, $96, $87, $80
	db $f6, $20, $95, $87

;@ def StartWaveSFX1(id: a)
;@ path: sound/sfx/wave
;@ Wave effect 1, the second half of the tetris jingle (UpdateSFX7
;@ requests it): four notes on Waveform1, the first sliding up.
;@ writes: wWaveSFXSlot
;@ test: id = 1
;@ sig: 46ee131c
StartWaveSFX1::
;> StartWaveSFX(id, Waveform1)
	ld hl, Waveform1
	call StartWaveSFX
;> mem[addr(wWaveSFXPlaying) + 5] = mem[WaveSFX1Regs + 3]     # pitch (NR33)
	ld hl, WaveSFX1Regs + 3
	ld a, [hl]
	ld [wWaveSFXPlaying + 5], a
;> mem[addr(wWaveSFXPlaying) + 4] = 1                         # slide up
	ld a, $01
	ld [wWaveSFXPlaying + 4], a
;> WriteWaveRegs(WaveSFX1Regs)
	ld hl, WaveSFX1Regs

.write:
	jp WriteWaveRegs

;@ def WaveSFX1Note2()
;@ path: sound/sfx/wave
;@ Second note of wave effect 1: held.
;@ writes: wWaveSFXSlot
;@ sig: cdecff41
WaveSFX1Note2::
;> mem[addr(wWaveSFXPlaying) + 4] = 0
	ld a, $00
	ld [wWaveSFXPlaying + 4], a
;> mem[addr(wWaveSFXPlaying) + 5] = mem[WaveSFX1Regs + 8]
	ld hl, WaveSFX1Regs + 8
	ld a, [hl]
	ld [wWaveSFXPlaying + 5], a
;> WriteWaveRegs(WaveSFX1Regs + 5)
	ld hl, WaveSFX1Regs + 5
	jr StartWaveSFX1.write

;@ def WaveSFX1Note3()
;@ path: sound/sfx/wave
;@ Third note of wave effect 1: slides up.
;@ writes: wWaveSFXSlot
;@ sig: d23327fb
WaveSFX1Note3::
;> mem[addr(wWaveSFXPlaying) + 4] = 1
	ld a, $01
	ld [wWaveSFXPlaying + 4], a
;> mem[addr(wWaveSFXPlaying) + 5] = mem[WaveSFX1Regs + 13]
	ld hl, WaveSFX1Regs + 13
	ld a, [hl]
	ld [wWaveSFXPlaying + 5], a
;> WriteWaveRegs(WaveSFX1Regs + 10)
	ld hl, WaveSFX1Regs + 10
	jr StartWaveSFX1.write

;@ def WaveSFX1Note4()
;@ path: sound/sfx/wave
;@ Last note of wave effect 1: slides down.
;@ writes: wWaveSFXSlot
;@ sig: c708c645
WaveSFX1Note4::
;> mem[addr(wWaveSFXPlaying) + 4] = 2
	ld a, $02
	ld [wWaveSFXPlaying + 4], a
;> mem[addr(wWaveSFXPlaying) + 5] = mem[WaveSFX1Regs + 18]
	ld hl, WaveSFX1Regs + 18
	ld a, [hl]
	ld [wWaveSFXPlaying + 5], a
;> WriteWaveRegs(WaveSFX1Regs + 15)
	ld hl, WaveSFX1Regs + 15
	jr StartWaveSFX1.write

;@ def UpdateWaveSFX1()
;@ path: sound/sfx/wave
;@ Every frame: new notes at frames 9, 19 and 23, the end at frame 32; in
;@ between the pitch slides by 2 per frame (+4: 1 = up, 2 = down).
;@ test: mem[0xDFF4] = rng.choice([8, 0x12, 0x16, 0x1F, rand(0, 0x1F)])
;@ test: mem[0xDFF5] = rand(0, 3)
;@ sig: bbf51a90
UpdateWaveSFX1::
;> step = mem[addr(wWaveSFXPlaying) + 3] = u8(mem[addr(wWaveSFXPlaying) + 3] + 1)
	ld hl, wWaveSFXPlaying + 3
	inc [hl]
	ld a, [hli]
;> if step == 0x09: return WaveSFX1Note2()
	cp $09
	jr z, WaveSFX1Note2

;> if step == 0x13: return WaveSFX1Note3()
	cp $13
	jr z, WaveSFX1Note3

;> if step == 0x17: return WaveSFX1Note4()
	cp $17
	jr z, WaveSFX1Note4

;> if step == 0x20: return StopWaveSFX()
	cp $20
	jr z, StopWaveSFX

;> slide = mem[addr(wWaveSFXPlaying) + 4]
	ld a, [hli]
;> if slide == 0: return
	cp $00
	ret z

;> if slide == 1:
	cp $01
	jr z, .up

;>@up     mem[addr(wWaveSFXPlaying) + 5] = u8(mem[addr(wWaveSFXPlaying) + 5] + 2)
;> elif slide == 2:
	cp $02
	jr z, .down

;>@down     mem[addr(wWaveSFXPlaying) + 5] = u8(mem[addr(wWaveSFXPlaying) + 5] - 2)
;> else:
;>     return
	ret

;=@up
.up
	inc [hl]
	inc [hl]
	jr .write

;=@down
.down
	dec [hl]
	dec [hl]

;> rNR33 = mem[addr(wWaveSFXPlaying) + 5]
.write
	ld a, [hl]
	ldh [rNR33], a
	ret


;@ def StopWaveSFX()
;@ path: sound/sfx/wave
;@ Ends the wave effect, gives all four channels back to the music and
;@ puts the music's waveform back (Waveform3 for song 5, else PauseWave).
;@ writes: wWaveSFXPlaying
;@ reads: wCurrentSong
;@ test: wCurrentSong = rng.choice([5, rand(0, 0x11)])
;@ sig: 748bf0da
StopWaveSFX::
;> wWaveSFXPlaying = 0
	xor a
	ld [wWaveSFXPlaying], a
;> rNR30 = 0
	ldh [rNR30], a
;> wChannel3[0x0F] &= 0x7F
	ld hl, wChannel3 + $0F
	res 7, [hl]
;> wChannel1[0x0F] &= 0x7F
	ld hl, wChannel1 + $0F
	res 7, [hl]
;> wChannel2[0x0F] &= 0x7F
	ld hl, wChannel2 + $0F
	res 7, [hl]
;> wChannel4[0x0F] &= 0x7F
	ld hl, wChannel4 + $0F
	res 7, [hl]
;> if wCurrentSong == 5:
	ld a, [wCurrentSong]
	cp $05
	jr z, .song5

;>@song5     LoadWaveRAM(Waveform3)
;> else:
;>     LoadWaveRAM(PauseWave)
	ld hl, PauseWave
	jr StartWaveSFX.loadWave

;=@song5
.song5
	ld hl, Waveform3
	jr StartWaveSFX.loadWave

;@ def StartWaveSFX(id: a, wave: hl)
;@ path: sound/sfx/wave
;@ Starts a wave channel sound effect: all four music channels are taken
;@ over (bit 7 of their flags), and the effect's waveform is loaded.
;@ writes: wWaveSFXPlaying, wChannel1, wChannel2, wChannel3, wChannel4, rNR30, wWaveSFXSlot
;@ test: id = rand(1, 2)
;@ test: wave = rand(0x6400, 0x7F00)
;@ sig: dca2aeb5
StartWaveSFX::
;> wWaveSFXPlaying = id
	push hl
	ld [wWaveSFXPlaying], a
;> wChannel3[0x0F] |= 0x80                          # music keeps off this channel
	ld hl, wChannel3 + $0F
	set 7, [hl]
;> mem[addr(wWaveSFXPlaying) + 3:addr(wWaveSFXPlaying) + 6] = [0, 0, 0]
	xor a
	ld [wWaveSFXPlaying + 3], a
	ld [wWaveSFXPlaying + 4], a
	ld [wWaveSFXPlaying + 5], a
;> rNR30 = 0                                        # wave DAC off while loading
	ldh [rNR30], a
;> wChannel1[0x0F] |= 0x80
	ld hl, wChannel1 + $0F
	set 7, [hl]
;> wChannel2[0x0F] |= 0x80
	ld hl, wChannel2 + $0F
	set 7, [hl]
;> wChannel4[0x0F] |= 0x80
	ld hl, wChannel4 + $0F
	set 7, [hl]
;> LoadWaveRAM(wave)
	pop hl
.loadWave:
	call LoadWaveRAM
	ret



;@ def StartSFX(period: a, regs: hl, slot: de)
;@ path: sound/sfx/common
;@ Common start of a sound effect. `slot` is its slot's frame counter; the
;@ bytes around it are: playing id, frame counter, period, step, spare.
;@ Writes the effect's first register values to its channel.
;@ reads: wSndTemp
;@ clobbers: a, b, c, e, hl
;@ test: period = rand(1, 8)
;@ test: regs = rand(0x6400, 0x7F00)
;@ test: slot = rng.choice([0xDFE2, 0xDFF2, 0xDFFA, 0xDFEA])
;@ sig: 093f4441
StartSFX::
;> mem[slot - 1] = wSndTemp                        # which effect plays
	push af
	dec e
	ld a, [wSndTemp]
	ld [de], a
	inc e
	pop af
;> mem[slot + 1] = period                          # frames per step
	inc e
	ld [de], a
	dec e
;> mem[slot] = 0                                   # frame counter
	xor a
	ld [de], a
;> mem[slot + 2] = 0                               # step
	inc e
	inc e
	ld [de], a
;> mem[slot + 3] = 0                               # spare
	inc e
	ld [de], a
;> if lo(slot + 3) == 0xE5: WriteSquare1Regs(regs)     # square slot
	ld a, e
	cp $e5
	jr z, WriteSquare1Regs

;> elif lo(slot + 3) == 0xF5: WriteWaveRegs(regs)      # wave slot
	cp $f5
	jr z, WriteWaveRegs

;> elif lo(slot + 3) == 0xFD: WriteNoiseRegs(regs)     # noise slot
	cp $fd
	jr z, WriteNoiseRegs

;> return
	ret

;@ def WriteSquare1Regs(regs: hl) -> hl
;@ path: sound/sfx/common
;@ Writes 5 bytes from regs to NR10-NR14.
;@ test: regs = rand(0x0000, 0x7F00)
;@ sig: 7ca6dd10
WriteSquare1Regs::
;> return WriteRegs(regs, 0x10, 5)
	push bc
	ld c, LOW(rNR10)
	ld b, $05
	jr WriteRegs

;@ def WriteSquare2Regs(regs: hl) -> hl
;@ path: sound/sfx/common
;@ Writes 4 bytes from regs to NR21-NR24.
;@ test: regs = rand(0x0000, 0x7F00)
;@ sig: 7f2c4f72
WriteSquare2Regs::
;> return WriteRegs(regs, 0x16, 4)
	push bc
	ld c, LOW(rNR21)
	ld b, $04
	jr WriteRegs

;@ def WriteWaveRegs(regs: hl) -> hl
;@ path: sound/sfx/common
;@ Writes 5 bytes from regs to NR30-NR34.
;@ test: regs = rand(0x0000, 0x7F00)
;@ sig: c2c270e0
WriteWaveRegs::
;> return WriteRegs(regs, 0x1A, 5)
	push bc
	ld c, LOW(rNR30)
	ld b, $05
	jr WriteRegs


;@ def WriteNoiseRegs(regs: hl) -> hl
;@ path: sound/sfx/common
;@ Writes 4 bytes from regs to NR41-NR44.
;@ test: regs = rand(0x0000, 0x7F00)
;@ sig: 6e72c2fa
WriteNoiseRegs::
;> return WriteRegs(regs, 0x20, 4)
	push bc
	ld c, LOW(rNR41)
	ld b, $04

;@ def WriteRegs(regs: hl, first: c, count: b) -> hl
;@ path: sound/sfx/common
;@ Copies `count` bytes from regs to the sound registers from $FF00 + first.
;@ Shared tail of the Write*Regs routines (they push bc first).
;@ test: skip pops a bc pushed by its callers
;@ sig: 0eb19ce1
WriteRegs::
;>@loop for i in range(count):
;>     mem[0xFF00 + first + i] = mem[regs + i]
	ld a, [hli]
	ldh [c], a
	inc c
;=@loop
	dec b
	jr nz, WriteRegs

;> return regs + count
	pop bc
	ret


;@ def StartSFXLookup(index: a, table: hl, slot: de) -> (hl, de)
;@ path: sound/sfx/common
;@ Remembers the requested sound (wSndTemp), then TableLookup.
;@ writes: wSndTemp
;@ test: index = rand(1, 8)
;@ test: table = rng.choice([0x6480, 0x6490, 0x64A0])
;@ test: slot = rng.choice([0xDFE0, 0xDFF8])
;@ sig: bfb6e5bf
StartSFXLookup::
;> wSndTemp = index
;> return TableLookup(index, table, (slot & 0xFF00) | lo(slot + 1))   # falls through
	inc e
	ld [wSndTemp], a

;@ def TableLookup(index: a, table: hl, slot: de) -> (hl, de)
;@ path: sound/sfx/common
;@ Returns entry `index` (1-based) of a table of addresses, and the slot
;@ pointer moved one byte on.
;@ clobbers: a, bc
;@ test: index = rand(1, 17)
;@ test: table = rng.choice([0x6480, 0x6490, 0x64A0, 0x64B0])
;@ test: slot = rng.choice([0xDFE0, 0xDFE8, 0xDFF8])
;@ sig: 267a559c
TableLookup::
;> slot = (slot & 0xFF00) | lo(slot + 1)
	inc e
;> offset = u8(2 * u8(index - 1))
	dec a
	sla a
;> ptr = table + offset
	ld c, a
	ld b, $00
	add hl, bc
;> entry = mem16[ptr]
	ld c, [hl]
	inc hl
	ld b, [hl]
	ld l, c
	ld h, b
	ld a, h
;> return entry, slot
	ret



;@ def SFXTick(slot: de) -> a
;@ path: sound/sfx/common
;@ Counts a sound effect's frames: returns 0 (and restarts the count) every
;@ `period` frames, otherwise the count so far.
;@ clobbers: hl
;@ test: slot = rng.choice([0xDFE2, 0xDFF2, 0xDFFA])
;@ test: mem[slot + 1] = rand(1, 8); mem[slot] = rand(0, mem[slot + 1] - 1)
;@ sig: 112db7a9
SFXTick::
;> count = mem[slot] = u8(mem[slot] + 1)
	push de
	ld l, e
	ld h, d
	inc [hl]
	ld a, [hli]
;> if count == mem[slot + 1]:
	cp [hl]
	jr nz, .done

;>     count = mem[slot] = 0
	dec l
	xor a
	ld [hl], a

;> return count
.done
	pop de
	ret

;@ def LoadWaveRAM(wave: hl) -> hl
;@ path: sound/sfx/common
;@ Copies a 16-byte waveform (32 samples) into wave RAM.
;@ test: wave = rand(0x0000, 0x7F00)
;@ sig: f0d05281
LoadWaveRAM::
;>@loop for i in range(16):
	push bc
	ld c, $30

;>     mem[WAVE_RAM + i] = mem[wave + i]
.loop
	ld a, [hli]
	ldh [c], a
;=@loop
	inc c
	ld a, c
	cp $40
	jr nz, .loop

;> return wave + 16
	pop bc
	ret


;@ def SoundInit()
;@ path: sound/api
;@ Stops everything: no song, no effects, all channels back to the music,
;@ both speakers on, all channels silenced.
;@ writes: wChannel1, wChannel2, wChannel3, wChannel4, wCurrentSong, wNoiseSFXPlaying, wPanMode, wSFXPlaying, wWaveSFXPlaying
;@ sig: 61eb0b09
SoundInit::
;> wSFXPlaying = 0
	xor a
	ld [wSFXPlaying], a
;> wCurrentSong = 0
	ld [wCurrentSong], a
;> wWaveSFXPlaying = 0
	ld [wWaveSFXPlaying], a
;> wNoiseSFXPlaying = 0
	ld [wNoiseSFXPlaying], a
;> wChannel1[0x0F] = 0
	ld [wChannel1 + $0F], a
;> wChannel2[0x0F] = 0
	ld [wChannel2 + $0F], a
;> wChannel3[0x0F] = 0
	ld [wChannel3 + $0F], a
;> wChannel4[0x0F] = 0
	ld [wChannel4 + $0F], a
;> rNR51 = 0xFF                                     # every channel to both speakers
	ld a, $ff
	ldh [rNR51], a
;> wPanMode = 3
;> SilenceChannels()                                # falls through
	ld a, $03
	ld [wPanMode], a

;@ def SilenceChannels()
;@ path: sound/api
;@ Envelopes to zero volume (restarted so they take effect), sweep off,
;@ wave DAC off.
;@ sig: d98ac311
SilenceChannels::
;> rNR12 = 0x08
	ld a, $08
	ldh [rNR12], a
;> rNR22 = 0x08
	ldh [rNR22], a
;> rNR42 = 0x08
	ldh [rNR42], a
;> rNR14 = 0x80                                     # restart with the silent envelope
	ld a, $80
	ldh [rNR14], a
;> rNR24 = 0x80
	ldh [rNR24], a
;> rNR44 = 0x80
	ldh [rNR44], a
;> rNR10 = 0
	xor a
	ldh [rNR10], a
;> rNR30 = 0
	ldh [rNR30], a
	ret


;@ def UpdateSquareSFX()
;@ path: sound/sfx/square
;@ The square channel part of the sound engine: start the requested effect
;@ (taking channel 1 from the music), or advance the one playing.
;@ test: wSFXRequest = rng.choice([0, 0, rand(1, 8)])
;@ test: wSFXPlaying = rand(0, 8)
;@ test: mem[0xDFE3] = rand(1, 8); mem[0xDFE2] = rand(0, mem[0xDFE3] - 1); mem[0xDFE4] = rand(0, 0x30)
;@ sig: ff49bdd7
UpdateSquareSFX::
;> req = wSFXRequest
	ld de, wSFXRequest
	ld a, [de]
;> if req:
	and a
	jr z, .update

;>     wChannel1[0x0F] |= 0x80
	ld hl, wChannel1 + $0F
	set 7, [hl]
;>     wSndTemp = req
;>     if req == 7: return StartSFX7(0x65, addr(wSFXSlot) + 2)   # a = high byte of the handler address
;>     return SFXStartHandlers[req - 1](slot=addr(wSFXSlot) + 2)
	ld hl, SFXStartHandlers
	call StartSFXLookup
	jp hl

;> if wSFXPlaying:
.update
	inc e
	ld a, [de]
	and a
	jr z, .done

;>     return SFXUpdateHandlers[wSFXPlaying - 1](slot=addr(wSFXSlot) + 2)
	ld hl, SFXUpdateHandlers
	call TableLookup
	jp hl

;> return
.done
	ret


;@ def UpdateNoiseSFX()
;@ path: sound/sfx/noise
;@ The noise channel part of the sound engine: start the requested effect
;@ (taking channel 4 from the music), or advance the one playing.
;@ test: wNoiseSFXRequest = rng.choice([0, 0, rand(1, 4)])
;@ test: wNoiseSFXPlaying = rand(0, 4)
;@ test: mem[0xDFFB] = rand(1, 0x30); mem[0xDFFA] = rand(0, mem[0xDFFB] - 1); mem[0xDFFC] = rand(0, 0x24)
;@ sig: 3538fe0b
UpdateNoiseSFX::
;> req = wNoiseSFXRequest
	ld de, wNoiseSFXRequest
	ld a, [de]
;> if req:
	and a
	jr z, .update

;>     wChannel4[0x0F] |= 0x80
	ld hl, wChannel4 + $0F
	set 7, [hl]
;>     wSndTemp = req
;>     return NoiseStartHandlers[req - 1](slot=addr(wNoiseSFXSlot) + 2)
	ld hl, NoiseStartHandlers
	call StartSFXLookup
	jp hl

;> if wNoiseSFXPlaying:
.update
	inc e
	ld a, [de]
	and a
	jr z, .done

;>     return NoiseUpdateHandlers[wNoiseSFXPlaying - 1](slot=addr(wNoiseSFXSlot) + 2)
	ld hl, NoiseUpdateHandlers
	call TableLookup
	jp hl

;> return
.done
	ret

;=@StartRequestedSong.stop
SongRequestStop:
	call SoundInit
	ret


;@ def StartRequestedSong()
;@ path: sound/music
;@ Starts the requested song ($FF = stop all sound).
;@ test: wMusicRequest = rng.choice([0, 0xFF, rand(1, 0x11)])
;@ sig: 5ea210c9
StartRequestedSong::
;> req = wMusicRequest
	ld hl, wMusicRequest
	ld a, [hli]
;> if req == 0: return
	and a
	ret z

;>@stop if req == 0xFF: return SoundInit()
	cp $ff
	jr z, SongRequestStop

;> wCurrentSong = req
	ld [hl], a
	ld b, a
;> header, _ = TableLookup(req & 0x1F, SongTable, 0)
	ld hl, SongTable
	and $1f
	call TableLookup
;> StartSong(header)
	call StartSong
;> SetSongPanning()
	call SetSongPanning
	ret


;@ def SetSongPanning()
;@ path: sound/music
;@ Loads the current song's panning settings from SongPanning.
;@ writes: wPanA, wPanB, wPanFrame, wPanMode, wPanPeriod, wPanToggle
;@ reads: wCurrentSong
;@ test: wCurrentSong = rand(0, 0x11)
;@ sig: f88fbc25
SetSongPanning::
;> if wCurrentSong == 0: return
	ld a, [wCurrentSong]
	and a
	ret z

;> p = SongPanning
	ld hl, SongPanning

;>@find for _ in range(wCurrentSong - 1):
.find
	dec a
	jr z, .found

;>     p += 4
	inc hl
	inc hl
	inc hl
	inc hl
;=@find
	jr .find

;> wPanMode = mem[p]
.found
	ld a, [hli]
	ld [wPanMode], a
;> wPanPeriod = mem[p + 1]
	ld a, [hli]
	ld [wPanPeriod], a
;> wPanA = mem[p + 2]
	ld a, [hli]
	ld [wPanA], a
;> wPanB = mem[p + 3]
	ld a, [hli]
	ld [wPanB], a
;> wPanFrame = 0
	xor a
	ld [wPanFrame], a
;> wPanToggle = 0
	ld [wPanToggle], a
	ret


;@ def UpdatePanning()
;@ path: sound/music
;@ Writes NR51 each frame. Mode 1 keeps wPanA, mode 3 plays everything on
;@ both speakers, other modes swap between wPanA and wPanB every
;@ wPanPeriod frames. Channels 3 and 4 go to both sides while an effect
;@ plays on them.
;@ reads: wCurrentSong, wNoiseSFXPlaying, wPanA, wPanB, wPanMode, wWaveSFXPlaying
;@ test: wCurrentSong = rng.choice([0, rand(1, 0x11)])
;@ test: wPanMode = rng.choice([1, 3, 0, 2])
;@ test: wPanPeriod = rand(1, 4); wPanFrame = rand(0, wPanPeriod - 1)
;@ test: wWaveSFXPlaying = rng.choice([0, 0, 1]); wNoiseSFXPlaying = rng.choice([0, 0, 2])
;@ sig: fd8122ed
UpdatePanning::
;>@cond if wCurrentSong == 0 or wPanMode == 3:
	ld a, [wCurrentSong]
	and a
	jr z, .all

;>@all     rNR51 = 0xFF
;>@ret     return
;> if wPanMode == 1:
	ld hl, wPanFrame
	ld a, [wPanMode]
	cp $01
	jr z, .fixed

;>@fixed     pan = wPanA
;=@cond
	cp $03
	jr z, .all

;> else:
;>     wPanFrame = u8(wPanFrame + 1)
	inc [hl]
;>     if wPanFrame != wPanPeriod:
	ld a, [hli]
	cp [hl]
	jr nz, .wait

;>@wn         if wNoiseSFXPlaying: rNR51 = 0xFF; return
;>@ww         if wWaveSFXPlaying: rNR51 = 0xFF; return
;>@wret         return
;>     wPanFrame = 0
	dec l
	ld [hl], $00
;>     wPanToggle = u8(wPanToggle + 1)
	inc l
	inc l
	inc [hl]
;>     pan = wPanA
	ld a, [wPanA]
;>     if wPanToggle & 1:
	bit 0, [hl]
	jp z, .set

;>         pan = wPanB
	ld a, [wPanB]

;> if wWaveSFXPlaying:                              # channel 3 on both sides
.set
	ld b, a
	ld a, [wWaveSFXPlaying]
	and a
	jr z, .noWave

;>     pan |= 0x44
	set 2, b
	set 6, b

;> if wNoiseSFXPlaying:                             # channel 4 on both sides
.noWave
	ld a, [wNoiseSFXPlaying]
	and a
	jr z, .noNoise

;>     pan |= 0x88
	set 3, b
	set 7, b

;> rNR51 = pan
.noNoise
	ld a, b

.write
	ldh [rNR51], a
;=@ret
	ret

;=@all
.all
	ld a, $ff
	jr .write

;=@fixed
.fixed
	ld a, [wPanA]
	jr .set

;=@wn
.wait
	ld a, [wNoiseSFXPlaying]
	and a
	jr nz, .all

;=@ww
	ld a, [wWaveSFXPlaying]
	and a
	jr nz, .all

;=@wret
	ret

SongPanning::
	db $01, $24, $ef, $56, $01, $00, $e5, $00, $01, $20, $fd, $00, $01, $20, $de, $f7
	db $03, $18, $7f, $f7, $03, $18, $f7, $7f, $03, $48, $df, $5b, $01, $18, $db, $e7
	db $01, $00, $fd, $f7, $03, $20, $7f, $f7, $01, $20, $ed, $f7, $01, $20, $ed, $f7
	db $01, $20, $ed, $f7, $01, $20, $ed, $f7, $01, $20, $ed, $f7, $01, $20, $ef, $f7
	db $01, $20, $ef, $f7

;@ def CopyIndirectWord(src: hl, dest: de)
;@ path: sound/music
;@ Copies the word that the pointer at src points to into dest (dest
;@ stays inside its 256-byte page).
;@ test: src = rng.choice([0xDF90, 0xDFA0, 0xDFB0, 0xDFC0]); w = rand(0x6F00, 0x7F00); mem[src] = w & 0xFF; mem[src + 1] = w >> 8
;@ test: dest = src + 4
;@ sig: b12c4f83
CopyIndirectWord::
;> p = mem16[src]
	ld a, [hli]
	ld c, a
	ld a, [hl]
	ld b, a
;> mem[dest] = mem[p]
	ld a, [bc]
	ld [de], a
;> mem[(dest & 0xFF00) | lo(dest + 1)] = mem[u16(p + 1)]
	inc e
	inc bc
	ld a, [bc]
	ld [de], a
	ret


;@ def CopyWord(src: hl, dest: de) -> hl
;@ path: sound/music
;@ Copies two bytes from src to dest (dest stays inside its page) and
;@ returns src moved past them.
;@ test: src = rand(0x6F00, 0x7F00)
;@ test: dest = rng.choice([0xDF81, 0xDF90, 0xDFA0, 0xDFB0, 0xDFC0])
;@ sig: b88c62c7
CopyWord::
;> mem[dest] = mem[src]
	ld a, [hli]
	ld [de], a
;> mem[(dest & 0xFF00) | lo(dest + 1)] = mem[src + 1]
	inc e
	ld a, [hli]
	ld [de], a
;> return src + 2
	ret


;@ def StartSong(header: hl)
;@ path: sound/music
;@ Sets up a song from its 11-byte header: flags, note length table and
;@ each channel's pattern list. Every channel starts at the first pattern
;@ of its list, with its note timer at 1 so the next update plays the
;@ first note.
;@ writes: wChannel1, wChannel2, wChannel3, wPanFrame, wPanToggle
;@ test: t = 0x64B0 + 2 * rand(0, 16); header = mem[t] | mem[t + 1] << 8
;@ sig: d99bdf30
StartSong::
;> SilenceChannels()
	call SilenceChannels
;> wPanFrame = 0
	xor a
	ld [wPanFrame], a
;> wPanToggle = 0
	ld [wPanToggle], a
;> wSongFlags = mem[header]
	ld de, wSongFlags
	ld b, $00
	ld a, [hli]
	ld [de], a
;> wNoteLengths = mem16[header + 1]
	inc e
	call CopyWord
;> mem16[wChannel1] = mem16[header + 3]               # pattern lists
	ld de, wChannel1
	call CopyWord
;> mem16[wChannel2] = mem16[header + 5]
	ld de, wChannel2
	call CopyWord
;> mem16[wChannel3] = mem16[header + 7]
	ld de, wChannel3
	call CopyWord
;> mem16[wChannel4] = mem16[header + 9]
	ld de, wChannel4
	call CopyWord
;> mem16[wChannel1 + 4] = mem16[mem16[wChannel1]]     # pattern pointer: first pattern
	ld hl, wChannel1
	ld de, wChannel1 + $04
	call CopyIndirectWord
;> mem16[wChannel2 + 4] = mem16[mem16[wChannel2]]
	ld hl, wChannel2
	ld de, wChannel2 + $04
	call CopyIndirectWord
;> mem16[wChannel3 + 4] = mem16[mem16[wChannel3]]
	ld hl, wChannel3
	ld de, wChannel3 + $04
	call CopyIndirectWord
;> mem16[wChannel4 + 4] = mem16[mem16[wChannel4]]
	ld hl, wChannel4
	ld de, wChannel4 + $04
	call CopyIndirectWord
;>@timers for ch in [wChannel1, wChannel2, wChannel3, wChannel4]:
	ld bc, $0410
	ld hl, wChannel1 + $02

;>     ch[2] = 1                                      # note timer
.timers
	ld [hl], $01
;=@timers
	ld a, c
	add l
	ld l, a
	dec b
	jr nz, .timers

;> wChannel1[0x0E] = 0
	xor a
	ld [wChannel1 + $0E], a
;> wChannel2[0x0E] = 0
	ld [wChannel2 + $0E], a
;> wChannel3[0x0E] = 0
	ld [wChannel3 + $0E], a
	ret

;=@InstrumentCommand.nr30
InstrumentLoadWave:
	push hl
	xor a
	ldh [rNR30], a
;=@InstrumentCommand.wave
	ld l, e
	ld h, d
	call LoadWaveRAM
	pop hl
	jr InstrumentCommand.next

;@ def InstrumentCommand(ptr: hl)
;@ path: sound/music
;@ Pattern command $9D: the next 3 bytes become the channel's instrument
;@ (+6..+8). On channel 3 the first two are a waveform address, loaded
;@ into wave RAM right away. Then the pattern goes on.
;@ test: n = rand(1, 4); wSndChannel = n; ch = 0xDF80 + 0x10 * n; ptr = ch + 4
;@ test: p = rand_ram(8); mem[ptr] = p & 0xFF; mem[ptr + 1] = p >> 8
;@ test: for c in range(ch + 0x10, 0xDFD0, 0x10): mem[c + 1] = 0
;@ sig: e7cf0b5e
InstrumentCommand::
;> AdvancePointer(ptr)
	call AdvancePointer
;> b0 = ReadPointer(ptr)
	call ReadPointer
	ld e, a
;> AdvancePointer(ptr)
	call AdvancePointer
;> b1 = ReadPointer(ptr)
	call ReadPointer
	ld d, a
;> AdvancePointer(ptr)
	call AdvancePointer
;> b2 = ReadPointer(ptr)
	call ReadPointer
	ld c, a
;> mem[ptr + 2] = b0
	inc l
	inc l
	ld [hl], e
;> mem[ptr + 3] = b1
	inc l
	ld [hl], d
;> mem[ptr + 4] = b2
	inc l
	ld [hl], c
	dec l
	dec l
	dec l
	dec l
;> channel = wSndChannel
	push hl
	ld hl, wSndChannel
	ld a, [hl]
	pop hl
;> if channel == 3:
	cp $03
	jr z, InstrumentLoadWave
;>@nr30     rNR30 = 0                                    # (InstrumentLoadWave, inside StartSong)
;>@wave     LoadWaveRAM(mem16[ptr + 2])

;> AdvancePointer(ptr)
.next:
	call AdvancePointer
;> return ReadPattern(ptr)
	jp ReadPattern


;@ def AdvancePointer(ptr: hl)
;@ path: sound/music
;@ Adds 1 to the word at ptr.
;@ test: ptr = rand_ram(2)
;@ sig: a23ec6ef
AdvancePointer::
;> p = mem16[ptr]
	push de
	ld a, [hli]
	ld e, a
	ld a, [hld]
	ld d, a
;> p = u16(p + 1)
	inc de

;> mem[ptr] = lo(p)
.store:
	ld a, e
	ld [hli], a
;> mem[ptr + 1] = hi(p)
	ld a, d
	ld [hld], a
	pop de
	ret


;@ def AdvancePointer2(ptr: hl)
;@ path: sound/music
;@ Adds 2 to the word at ptr.
;@ test: ptr = rand_ram(2)
;@ sig: 3e0d7f83
AdvancePointer2::
;> p = mem16[ptr]
	push de
	ld a, [hli]
	ld e, a
	ld a, [hld]
	ld d, a
;> p = u16(p + 2)
	inc de
	inc de
;> mem16[ptr] = p                                  # AdvancePointer.store
	jr AdvancePointer.store

;@ def ReadPointer(ptr: hl) -> a
;@ path: sound/music
;@ Reads the byte that the pointer at ptr points to (also left in b).
;@ test: ptr = rand_ram(2)
;@ sig: 77917b65
ReadPointer::
;> p = mem16[ptr]
	ld a, [hli]
	ld c, a
	ld a, [hld]
	ld b, a
;> return mem[p]
	ld a, [bc]
	ld b, a
	ret

;=@SustainNote.skip
SustainNoVibrato:
	pop hl
	jr SkipChannel

;@ def SustainNote(timer: hl)
;@ path: sound/music
;@ A frame in the middle of a note: channel 3 notes whose volume byte has
;@ bit 7 set drop to half volume 6 frames before the end; then vibrato.
;@ reads: wChannel3, wSndChannel
;@ test: n = rand(1, 4); wSndChannel = n; ch = 0xDF80 + 0x10 * n; timer = ch + 2
;@ test: mem[timer] = rng.choice([6, rand(1, 10)]); mem[ch + 0x0B] = rng.choice([0, 0, 1])
;@ test: mem[ch + 0x0F] = rng.choice([0, 0, 0x80]); mem[ch + 8] = rand(0, 255)
;@ test: for c in range(ch + 0x10, 0xDFD0, 0x10): mem[c + 1] = 0
;@ sig: aa14827c
SustainNote::
;> if wSndChannel == 3:
	ld a, [wSndChannel]
	cp $03
	jr nz, .vibrato

;>     if wChannel3[8] & 0x80:
	ld a, [wChannel3 + $08]
	bit 7, a
	jr z, .vibrato

;>         if mem[timer] == 6:
	ld a, [hl]
	cp $06
	jr nz, .vibrato

;>             rNR32 = 0x40                         # half volume
	ld a, $40
	ldh [rNR32], a

;> ch = timer - 2
.vibrato
	push hl
;> if mem[ch + 0x0B] == 0:                          # not a rest
	ld a, l
	add $09
	ld l, a
	ld a, [hl]
	and a
	jr nz, SustainNoVibrato

;>     if not mem[ch + 0x0F] & 0x80:                # no effect on the channel
	ld a, l
	add $04
	ld l, a
	bit 7, [hl]
	jr nz, SustainNoVibrato

;>         UpdateVibrato(timer)
;>@skip return SkipChannel(timer)                        # falls through (SustainNoVibrato, inside ReadPointer, also goes there)
	pop hl
	call UpdateVibrato

;@ def SkipChannel(timer: hl)
;@ path: sound/music
;@ Nothing more to do for this channel this frame.
;@ test: n = rand(1, 4); wSndChannel = n; ch = 0xDF80 + 0x10 * n; timer = ch + 2
;@ test: for c in range(ch + 0x10, 0xDFD0, 0x10): mem[c + 1] = 0
;@ sig: 0345d30d
SkipChannel::
;> return NextChannel(timer - 2)
	dec l
	dec l
	jp NextChannel


;@ def NextPattern(ptr: hl)
;@ path: sound/music
;@ Pattern byte $00: move on to the next pattern of the channel's list.
;@ A list word with high byte $00 ends the song (all sound stops and the
;@ rest of this frame's music update is skipped); $FFxx means the next
;@ word is where the list continues.
;@ test: n = rand(1, 4); wSndChannel = n; ch = 0xDF80 + 0x10 * n; ptr = ch + 4
;@ test: lst = rand_ram(8); mem[ch] = (lst - 2) & 0xFF; mem[ch + 1] = (lst - 2) >> 8
;@ test: mem[lst + 1] = rng.choice([0, 0xFF, 0x70, rand(1, 0xFE)])
;@ test: for c in range(ch + 0x10, 0xDFD0, 0x10): mem[c + 1] = 0
;@ sig: 8796e4ce
NextPattern::
;> ch = ptr - 4
	dec l
	dec l
	dec l
	dec l
;> AdvancePointer2(ch)                              # next word of the pattern list
	call AdvancePointer2

;>@loop while True:
;>     CopyIndirectWord(ch, ch + 4)                 # pattern pointer = list entry
.entry
	ld a, l
	add $04
	ld e, a
	ld d, h
	call CopyIndirectWord
;>     if mem[ch + 5] == 0:                         # end of the song
	cp $00
	jr z, .end

;>@end1         wCurrentSong = 0
;>@end2         SoundInit()
;>@end3         return
;>     if mem[ch + 5] != 0xFF:
	cp $ff
	jr z, .loop

;>         return NextNote(ch + 2)
	inc l
	jp NextNote

;>     AdvancePointer2(ch)                          # $FFFF: the list continues at the next word
.loop
	dec l
	push hl
	call AdvancePointer2
;>     lo_ = ReadPointer(ch)
	call ReadPointer
	ld e, a
;>     AdvancePointer(ch)
	call AdvancePointer
;>     hi_ = ReadPointer(ch)
	call ReadPointer
	ld d, a
	pop hl
;>     mem[ch] = lo_
	ld a, e
	ld [hli], a
;>     mem[ch + 1] = hi_
	ld a, d
	ld [hld], a
;=@loop
	jr .entry

;=@end1
.end
	ld hl, wCurrentSong
	ld [hl], $00
;=@end2
	call SoundInit
;=@end3
	ret


;@ def UpdateMusic()
;@ path: sound/music
;@ One frame of the song: each of the 4 channels in turn.
;@ writes: wSndChannel
;@ test: wCurrentSong = rng.choice([0, rand(1, 0x11)])
;@ test: for c in range(0xDF90, 0xDFD0, 0x10): mem[c + 1] = rng.choice([0, rand(0x70, 0x7F)]); mem[c + 2] = rand(1, 3)
;@ sig: 3a9324cf
UpdateMusic::
;> if wCurrentSong == 0: return
	ld hl, wCurrentSong
	ld a, [hl]
	and a
	ret z

;> wSndChannel = 1
	ld a, $01
	ld [wSndChannel], a
;> return UpdateChannel(wChannel1)                  # falls through
	ld hl, wChannel1

;@ def UpdateChannel(ch: hl)
;@ path: sound/music
;@ A channel without a pattern list is skipped. Otherwise its note timer
;@ counts down; at 0 the next note is read.
;@ test: n = rand(1, 4); wSndChannel = n; ch = 0xDF80 + 0x10 * n
;@ test: mem[ch + 1] = rng.choice([0, rand(0x70, 0x7F)]); mem[ch + 2] = rand(1, 3)
;@ test: for c in range(ch + 0x10, 0xDFD0, 0x10): mem[c + 1] = 0
;@ sig: 68ddc865
UpdateChannel::
;> timer = ch + 2
;> if mem[ch + 1] == 0: return SkipChannel(timer)
	inc l
	ld a, [hli]
	and a
	jp z, SkipChannel

;> mem[timer] = u8(mem[timer] - 1)
	dec [hl]
;> if mem[timer]: return SustainNote(timer)
;> return NextNote(timer)                           # falls through
	jp nz, SustainNote

;@ def NextNote(timer: hl)
;@ path: sound/music
;@ test: n = rand(1, 4); wSndChannel = n; ch = 0xDF80 + 0x10 * n; timer = ch + 2
;@ test: for c in range(ch + 0x10, 0xDFD0, 0x10): mem[c + 1] = 0
;@ sig: 4a3015b2
NextNote::
;> return ReadPattern(timer + 2)                    # falls through
	inc l
	inc l

;@ def ReadPattern(ptr: hl)
;@ path: sound/music
;@ Reads the channel's pattern at ptr (the channel's +4): $00 ends the
;@ pattern, $9D sets the instrument, $Ax sets the note length (from the
;@ song's note length table) for this and later notes; then comes the
;@ note: $01 is a rest, other values index NoteFrequencies (on channel 4:
;@ NoiseInstruments).
;@ reads: wSndChannel
;@ test: n = rand(1, 4); wSndChannel = n; ch = 0xDF80 + 0x10 * n; ptr = ch + 4
;@ test: p = rand_ram(8); mem[ptr] = p & 0xFF; mem[ptr + 1] = p >> 8; mem[ch + 7] = rng.choice([0, 0, 0x6E])
;@ test: mem[p] = rng.choice([0, 1, 0x9D, 0xA3, rand(2, 0x8E), rand(0, 255)]); mem[p + 1] = rng.choice([1, rand(2, 0x8E)])
;@ test: for c in range(ch + 0x10, 0xDFD0, 0x10): mem[c + 1] = 0
;@ sig: 1e60c8be
ReadPattern::
;> ch = ptr - 4
;> b = ReadPointer(ptr)
	call ReadPointer
;> if b == 0: return NextPattern(ptr)
	cp $00
	jp z, NextPattern

;> if b == 0x9D: return InstrumentCommand(ptr)
	cp $9d
	jp z, InstrumentCommand

;> if b & 0xF0 == 0xA0:
	and $f0
	cp $a0
	jr nz, .note

;>     idx = b & 0x0F
	ld a, b
	and $0f
	ld c, a
	ld b, $00
	push hl
;>     table = wNoteLengths
	ld de, wNoteLengths
	ld a, [de]
	ld l, a
	inc de
	ld a, [de]
	ld h, a
;>     length = mem[u16(table + idx)]
	add hl, bc
	ld a, [hl]
	pop hl
;>     mem[ch + 3] = length                         # note length
	dec l
	ld [hli], a
;>     AdvancePointer(ptr)
	call AdvancePointer
;>     b = ReadPointer(ptr)
	call ReadPointer

;> note = b
.note
	ld a, b
	ld c, a
	ld b, $00
;> AdvancePointer(ptr)
	call AdvancePointer
;> if wSndChannel == 4: return NoiseNote(note, ptr)
	ld a, [wSndChannel]
	cp $04
	jp z, NoiseNote

;> freq = ch + 9                                    # frequency (+9, +10)
	push hl
	ld a, l
	add $05
	ld l, a
	ld e, l
	ld d, h
;> rest = ch + 0x0B
	inc l
	inc l
;> if note == 1:                                    # rest
	ld a, c
	cp $01
	jr z, .rest

;>@rest     mem[rest] = 1
;>@restplay     return PlayNote(ptr, lo(ch + 9))
;> mem[rest] = 0
	ld [hl], $00
;> src = NoteFrequencies + note
	ld hl, NoteFrequencies
	add hl, bc
;> mem[freq] = mem[src]
	ld a, [hli]
	ld [de], a
;> mem[freq + 1] = mem[src + 1]
	inc e
	ld a, [hl]
	ld [de], a
;> return PlayNote(ptr, lo(ch + 0x0A))
	pop hl
	jp PlayNote

;=@rest
.rest
	ld [hl], $01
;=@restplay
	pop hl
	jr PlayNote

;@ def NoiseNote(note: bc, ptr: hl)
;@ path: sound/music
;@ Channel 4: the note byte picks a 5-byte noise instrument, copied to
;@ the channel's +6..+10 (envelope, unused, length, NR43, NR44).
;@ test: wSndChannel = 4; ptr = 0xDFC4
;@ test: note = rng.choice([1, 6, 11, 16, rand(0, 0x40)])
;@ sig: 508be192
NoiseNote::
;> dest = wChannel4 + 6
	push hl
	ld de, wChannel4 + $06
;> src = NoiseInstruments + note
	ld hl, NoiseInstruments
	add hl, bc

;>@copy for i in range(5):
;>     mem[dest + i] = mem[src + i]
.copy
	ld a, [hli]
	ld [de], a
;=@copy
	inc e
	ld a, e
	cp $cb
	jr nz, .copy

;> return InstrumentNote(0x20, 0xCB, ptr)   # NR41-NR44; e is $CB after the copy loop
	ld c, LOW(rNR41)
	ld hl, wChannel4 + $04
	jr InstrumentNote

;@ def PlayNote(ptr: hl, leftover: e)
;@ path: sound/music
;@ Starts the note on the channel's sound registers. Channel 3 first
;@ restarts the wave DAC (unless an effect has the channel) and uses its
;@ volume byte (+8) with length 0.
;@ reads: wChannel3, wSndChannel
;@ test: n = rand(1, 3); wSndChannel = n; ch = 0xDF80 + 0x10 * n; ptr = ch + 4
;@ test: leftover = rand(0, 255); mem[ch + 7] = rng.choice([0, 0, 0x6E]); mem[ch + 0x0B] = rng.choice([0, 0, 1])
;@ test: for c in range(ch + 0x10, 0xDFD0, 0x10): mem[c + 1] = 0
;@ sig: 006fc802
PlayNote::
;> if wSndChannel == 1:
	push hl
	ld a, [wSndChannel]
	cp $01
	jr z, .square1

;>@sq1     return InstrumentNote(0x11, leftover, ptr)  # NR11-NR14
;> if wSndChannel == 2:
	cp $02
	jr z, .square2

;>@sq2     return InstrumentNote(0x16, leftover, ptr)  # NR21-NR24
;> if not wChannel3[0x0F] & 0x80:
	ld c, LOW(rNR30)
	ld a, [wChannel3 + $0F]
	bit 7, a
	jr nz, .taken

;>     rNR30 = 0                                    # restart the wave DAC
	xor a
	ldh [c], a
;>     rNR30 = 0x80
	ld a, $80
	ldh [c], a

;> reg = 0x1B                                       # NR31-NR34
.taken
	inc c
;> vol = mem[ptr + 4]
	inc l
	inc l
	inc l
	inc l
	ld a, [hli]
	ld e, a
;> return WriteNote(reg, ptr + 5, 0, vol)
	ld d, $00
	jr WriteNote

;=@sq2
.square2
	ld c, LOW(rNR21)
	jr InstrumentNote

;=@sq1
.square1
	ld c, LOW(rNR10)
	ld a, $00
	inc c

;@ def InstrumentNote(reg: c, leftover: e, ptr: hl)
;@ path: sound/music
;@ Square and noise channels: duty/length from instrument byte +8 and the
;@ envelope from +6. If +7 is nonzero the envelope is whatever e held
;@ (the low byte of an address - some songs do this on channel 1).
;@ test: skip pops the pattern pointer its caller pushed
;@ sig: 2601140e
InstrumentNote::
;> ch = ptr - 4
;>@keep env = leftover                                   # kept if +7 is nonzero (InstrumentNoteKeepEnv, inside NextChannel)
;> if mem[ch + 7] == 0:
	inc l
	inc l
	inc l
	ld a, [hld]
	and a
	jr nz, InstrumentNoteKeepEnv

;>     env = mem[ch + 6]
	ld a, [hli]
	ld e, a

;> duty = mem[ch + 8]
;> return WriteNote(reg, ch + 9, duty, env)         # falls through
.duty:
	inc l
	ld a, [hli]
	ld d, a

;@ def WriteNote(reg: c, freq: hl, duty: d, env: e)
;@ path: sound/music
;@ Writes the 4 registers of the note (a rest gets envelope $01: silent)
;@ unless an effect has the channel, restarts the vibrato count and
;@ reloads the note timer from the note length.
;@ test: skip pops the pattern pointer its caller pushed
;@ sig: 50a55b61
WriteNote::
;> ch = freq - 9
;> if mem[ch + 0x0B]:                               # rest
	push hl
	inc l
	inc l
	ld a, [hli]
	and a
	jr z, .sound

;>     env = 1
	ld e, $01

;> mem[ch + 0x0E] = 0                               # vibrato count
.sound
	inc l
	inc l
	ld [hl], $00
;> flags = mem[ch + 0x0F]
	inc l
	ld a, [hl]
	pop hl
;> if not flags & 0x80:
	bit 7, a
	jr nz, .done

;>     mem[0xFF00 + reg] = duty
	ld a, d
	ldh [c], a
;>     mem[0xFF00 + reg + 1] = env
	inc c
	ld a, e
	ldh [c], a
;>     mem[0xFF00 + reg + 2] = mem[ch + 9]
	inc c
	ld a, [hli]
	ldh [c], a
;>     mem[0xFF00 + reg + 3] = mem[ch + 0x0A] | 0x80   # trigger
	inc c
	ld a, [hl]
	or $80
	ldh [c], a
;>     mem[ch + 0x0F] &= 0xFE
	ld a, l
	or $05
	ld l, a
	res 0, [hl]

;> mem[ch + 2] = mem[ch + 3]                        # note timer = note length
.done
	pop hl
	dec l
	ld a, [hld]
	ld [hld], a
;> return NextChannel(ch)                           # falls through
	dec l

;@ def NextChannel(ch: hl)
;@ path: sound/music
;@ On to the next channel; after channel 4 the vibrato counts of channels
;@ 1-3 go up.
;@ test: n = rand(1, 4); wSndChannel = n; ch = 0xDF80 + 0x10 * n
;@ test: for c in range(ch + 0x10, 0xDFD0, 0x10): mem[c + 1] = 0
;@ sig: bb18d61b
NextChannel::
;> if wSndChannel == 4:
	ld de, wSndChannel
	ld a, [de]
	cp $04
	jr z, .done

;>@d1     wChannel1[0x0E] += 1
;>@d2     wChannel2[0x0E] += 1
;>@d3     wChannel3[0x0E] += 1
;>@dret     return
;> wSndChannel += 1
	inc a
	ld [de], a
;> return UpdateChannel(u16(ch + 0x10))
	ld de, $0010
	add hl, de
	jp UpdateChannel

;=@d1
.done
	ld hl, wChannel1 + $0E
	inc [hl]
;=@d2
	ld hl, wChannel2 + $0E
	inc [hl]
;=@d3
	ld hl, wChannel3 + $0E
	inc [hl]
;=@dret
	ret

;=@InstrumentNote.keep
InstrumentNoteKeepEnv:
	ld b, $00
	push hl
	pop hl
	inc l
	jr InstrumentNote.duty

;@ def VibratoOffset(count: b, table: de) -> e
;@ path: sound/music
;@ Byte count / 2 of the vibrato table.
;@ test: count = rand(0, 255)
;@ test: table = 0x6DCB
;@ sig: b6c10ea3
VibratoOffset::
;> idx = count >> 1
	ld a, b
	srl a
;> p = table + idx
	ld l, a
	ld h, $00
	add hl, de
;> return mem[p]
	ld e, [hl]
	ret


;@ def UpdateVibrato(timer: hl)
;@ path: sound/music
;@ Channels 1-3 with a vibrato type (low nibble of instrument byte +8):
;@ the frequency gets a signed 4-bit offset from VibratoTable, one nibble
;@ per frame of the note (high nibble first). Only type 1 exists; the
;@ code for other types is skipped by an unconditional jr.
;@ writes: wSndTemp
;@ reads: wSndChannel, wSndTemp
;@ test: n = rand(1, 4); wSndChannel = n; ch = 0xDF80 + 0x10 * n; timer = ch + 2
;@ test: mem[ch + 8] = rng.choice([0, 1, rand(0, 255)]); mem[ch + 0x0E] = rand(0, 0x6D)
;@ sig: 3ba6c62d
UpdateVibrato::
;> ch = timer - 2
;> kind = mem[ch + 8] & 0x0F
	push hl
	ld a, l
	add $06
	ld l, a
	ld a, [hl]
	and $0f
;> if kind == 0: return
	jr z, .done

;> wSndTemp = kind
	ld [wSndTemp], a
;> if wSndChannel == 1: reg = 0x13                  # NR13/NR14
	ld a, [wSndChannel]
	ld c, LOW(rNR13)
	cp $01
	jr z, .vibrato

;> elif wSndChannel == 2: reg = 0x18                # NR23/NR24
	ld c, LOW(rNR23)
	cp $02
	jr z, .vibrato

;> elif wSndChannel == 3: reg = 0x1D                # NR33/NR34
	ld c, LOW(rNR33)
	cp $03
	jr z, .vibrato

;> else: return
.done
	pop hl
	ret

;> base = mem16[ch + 9]
.vibrato
	inc l
	ld a, [hli]
	ld e, a
	ld a, [hl]
	ld d, a
	push de
;> count = mem[ch + 0x0E]
	ld a, l
	add $04
	ld l, a
	ld b, [hl]
;> e = VibratoOffset(count, VibratoTable)           # wSndTemp == 1 is tested, but the jr is unconditional
	ld a, [wSndTemp]
	cp $01
	jr .type1

	db $fe, $03, $18, $00, $21, $ff, $ff, $18, $1c

.type1
	ld de, VibratoTable
	call VibratoOffset
;> nibble = e
;> if not count & 1:
	bit 0, b
	jr nz, .low

;>     nibble = e >> 4                              # high nibble first
	swap e

;> nibble &= 0x0F
.low
	ld a, e
	and $0f
;> if nibble & 8:                                   # signed
	bit 3, a
	jr z, .positive

;>     offset = nibble - 16
	ld h, $ff
	or $f0
	jr .add

;> else:
;>     offset = nibble
.positive
	ld h, $00

;> f = u16(base + offset)
.add
	ld l, a
	pop de
	add hl, de
;> mem[0xFF00 + reg] = lo(f)
	ld a, l
	ldh [c], a
;> mem[0xFF00 + reg + 1] = hi(f)
	inc c
	ld a, h
	ldh [c], a
	jr .done
VibratoTable::
	db $00, $00, $00, $00, $00, $00, $10, $00, $0f, $00, $00, $11, $00, $0f, $f0, $01
	db $12, $10, $ff, $ef, $01, $12, $10, $ff, $ef, $01, $12, $10, $ff, $ef, $01, $12
	db $10, $ff, $ef, $01, $12, $10, $ff, $ef, $01, $12, $10, $ff, $ef, $01, $12, $10
	db $ff, $ef, $01, $12, $10, $ff, $ef

; Frequency register value of each note (2 bytes per note)
NoteFrequencies::
	db $00, $0f, $2c, $00, $9c, $00, $06, $01, $6b
	db $01, $c9, $01, $23, $02, $77, $02, $c6, $02, $12, $03, $56, $03, $9b, $03, $da
	db $03, $16, $04, $4e, $04, $83, $04, $b5, $04, $e5, $04, $11, $05, $3b, $05, $63
	db $05, $89, $05, $ac, $05, $ce, $05, $ed, $05, $0a, $06, $27, $06, $42, $06, $5b
	db $06, $72, $06, $89, $06, $9e, $06, $b2, $06, $c4, $06, $d6, $06, $e7, $06, $f7
	db $06, $06, $07, $14, $07, $21, $07, $2d, $07, $39, $07, $44, $07, $4f, $07, $59
	db $07, $62, $07, $6b, $07, $73, $07, $7b, $07, $83, $07, $8a, $07, $90, $07, $97
	db $07, $9d, $07, $a2, $07, $a7, $07, $ac, $07, $b1, $07, $b6, $07, $ba, $07, $be
	db $07, $c1, $07, $c4, $07, $c8, $07, $cb, $07, $ce, $07, $d1, $07, $d4, $07, $d6
	db $07, $d9, $07, $db, $07, $dd, $07, $df, $07

; Noise channel instruments, indexed by note byte
NoiseInstruments::
	db $00, $00, $00, $00, $00, $c0, $a1
	db $00, $3a, $00, $c0, $b1, $00, $29, $01, $c0, $61, $00, $3a, $00, $c0

; Wave RAM contents (16 bytes = 32 4-bit samples)
Waveform1::
	db $12, $34
	db $45, $67, $9a, $bc, $de, $fe, $98, $7a, $b7, $be, $a8, $76, $54, $31

Waveform2::
	db $01, $23
	db $44, $55, $67, $88, $9a, $bb, $a9, $88, $76, $55, $44, $33, $22, $11

Waveform3::
	db $01, $23
	db $45, $67, $89, $ab, $cd, $ef, $fe, $dc, $ba, $98, $76, $54, $32, $10

Waveform4::
	db $a1, $82
	db $23, $34, $45, $56, $67, $78, $89, $9a, $ab, $bc, $cd, $64, $32, $10

; Waveform loaded for the pause jingle
PauseWave::
	db $11, $23
	db $56, $78, $99, $98, $76, $67, $9a, $df, $fe, $c9, $85, $42, $11, $31

; Note length tables: frames per note length code $A0-$AF
;@ path: sound/music/songs
NoteLengths1::
	db $02, $04
	db $08, $10, $20, $40, $0c, $18, $30, $05, $00, $01, $03, $05, $0a, $14, $28, $50
	db $0f, $1e, $3c

;@ path: sound/music/songs
NoteLengths2::
	db $03, $06, $0c, $18, $30, $60, $12, $24, $48, $08, $10, $00, $07
	db $0e, $1c, $38, $70, $15, $2a, $54, $04, $08, $10, $20, $40, $80, $18, $30, $60
	db $04, $09, $12, $24, $48, $90, $1b, $36, $6c, $0c, $18, $04, $0a, $14, $28, $50
	db $a0, $1e, $3c, $78

; Song data of the sound engine (decoded by tools/songdata.py): per song a header,
; a pattern list per channel and the patterns. Lists end with dw $0000 (song over)
; or dw $FFFF, Target (continue there - the loop). Pattern bytes: $9D + 3 = instrument,
; $Ax = note length, $01 = rest, $00 = end, others = notes.

; Song $01: High score name entry
;@ path: sound/music/songs
Song01Header::
	db $00
	dw NoteLengths2
	dw Song01Sq1, Song01Sq2, Song01Wave, Song01Noise

; Song $02: Lines cleared (type B win) jingle
;@ path: sound/music/songs
Song02Header::
	db $00
	dw $6f05
	dw Song02Sq1, Song02Sq2, Song02Wave, Song02Noise

; Song $03: Title screen
;@ path: sound/music/songs
Song03Header::
	db $00
	dw NoteLengths2
	dw Song03Sq1, Song03Sq2, Song03Wave, Song03Noise

; Song $04: Game over jingle
;@ path: sound/music/songs
Song04Header::
	db $00
	dw NoteLengths1
	dw Song04Sq1, Song04Sq2, Song04Wave, $0000

; Song $05: A-TYPE music (Korobeiniki)
;@ path: sound/music/songs
Song05Header::
	db $00
	dw NoteLengths2
	dw Song05Sq1, Song05Sq2, Song05Wave, Song05Noise

; Song $06: B-TYPE music
;@ path: sound/music/songs
Song06Header::
	db $00
	dw NoteLengths2
	dw Song06Sq1, Song06Sq2, Song06Wave, Song06Noise

; Song $07: C-TYPE music
;@ path: sound/music/songs
Song07Header::
	db $00
	dw NoteLengths2
	dw Song07Sq1, Song07Sq2, $0000, $0000

; Song $08: 2-player danger (stack 12+ rows)
;@ path: sound/music/songs
Song08Header::
	db $00
	dw $6f05
	dw Song08Sq1, Song08Sq2, Song08Wave, Song08Noise

; Song $09: 2-player round over
;@ path: sound/music/songs
Song09Header::
	db $00
	dw NoteLengths2
	dw Song09Sq1, Song09Sq2, Song09Wave, Song09Noise

; Song $0A: Dancers ending, height 0
;@ path: sound/music/songs
Song0AHeader::
	db $00
	dw NoteLengths2
	dw $0000, Song0ASq2, $0000, $0000

; Song $0B: Dancers ending, height 1
;@ path: sound/music/songs
Song0BHeader::
	db $00
	dw NoteLengths2
	dw $0000, Song0BSq2, Song0BWave, $0000

; Song $0C: Dancers ending, height 2
;@ path: sound/music/songs
Song0CHeader::
	db $00
	dw NoteLengths2
	dw Song0CSq1, Song0CSq2, Song0CWave, $0000

; Song $0D: Dancers ending, height 3
;@ path: sound/music/songs
Song0DHeader::
	db $00
	dw NoteLengths2
	dw Song0DSq1, Song0DSq2, Song0DWave, Song0DNoise

; Song $0E: Dancers ending, height 4
;@ path: sound/music/songs
Song0EHeader::
	db $00
	dw NoteLengths2
	dw Song0ESq1, Song0ESq2, Song0EWave, Song0ENoise

; Song $0F: Dancers ending, height 5
;@ path: sound/music/songs
Song0FHeader::
	db $00
	dw NoteLengths2
	dw Song0FSq1, Song0FSq2, Song0FWave, Song0FNoise

; Song $10: Rocket / shuttle launch
;@ path: sound/music/songs
Song10Header::
	db $00
	dw $6f2b
	dw Song10Sq1, Song10Sq2, Song10Wave, $0000

; Song $11: 2-player match over
;@ path: sound/music/songs
Song11Header::
	db $00
	dw NoteLengths2
	dw Song11Sq1, Song11Sq2, Song11Wave, $0000

;@ path: sound/music/songs
Song07Sq2::
	dw Song07Pat5, Song07Pat6, Song07Pat5, Song07Pat7, Song07Pat8, $FFFF, Song07Sq2

;@ path: sound/music/songs
Song07Sq1::
	dw Song07Pat1, Song07Pat2, Song07Pat1, Song07Pat3, Song07Pat4, $FFFF, Song07Sq1

;@ path: sound/music/songs
Song07Pat5::
	db $9d, $74, $00, $41, $a2, $44, $4c, $56, $4c, $42, $4c, $44, $4c, $3e, $4c, $3c
	db $4c, $44, $4c, $56, $4c, $42, $4c, $44, $4c, $3e, $4c, $3c, $4c, $00

;@ path: sound/music/songs
Song07Pat6::
	db $44, $4c, $44, $3e, $4e, $48, $42, $48, $42, $3a, $4c, $44, $3e, $4c, $48, $44
	db $42, $3e, $3c, $34, $3c, $42, $4c, $48, $00

;@ path: sound/music/songs
Song07Pat7::
	db $44, $4c, $44, $3e, $4e, $48, $42, $48, $42, $3a, $52, $48, $4c, $52, $4c, $44
	db $3a, $42, $a8, $44, $00

;@ path: sound/music/songs
Song07Pat1::
	db $9d, $64, $00, $41, $a3, $26, $3e, $3c, $26, $2c, $34, $3e, $36, $34, $3e, $2c
	db $34, $00

;@ path: sound/music/songs
Song07Pat2::
	db $26, $3e, $30, $22, $3a, $2c, $1e, $36, $30, $a2, $34, $36, $34, $30, $2c, $2a
	db $00

;@ path: sound/music/songs
Song07Pat3::
	db $a3, $26, $3e, $30, $22, $3a, $2a, $2c, $34, $34, $2c, $22, $14, $00

;@ path: sound/music/songs
Song07Pat8::
	db $a2, $52, $4e, $4c, $48, $44, $42, $44, $48, $4c, $44, $48, $4e, $4c, $4e, $a3
	db $52, $42, $a2, $44, $48, $a3, $4c, $48, $4c, $56, $50, $a2, $56, $5a, $a3, $5c
	db $5a, $a2, $56, $52, $50, $4c, $50, $4a, $a8, $4c, $a7, $52, $a1, $56, $58, $a3
	db $56, $a2, $52, $4e, $52, $4c, $4e, $48, $a7, $56, $a1, $5a, $5c, $a3, $5a, $a2
	db $56, $54, $56, $50, $54, $4c, $5a, $54, $4c, $54, $5a, $60, $66, $54, $64, $54
	db $60, $54, $a3, $5c, $a2, $60, $5c, $5a, $5c, $a1, $56, $5a, $a4, $56, $a2, $01
	db $00

;@ path: sound/music/songs
Song07Pat4::
	db $a2, $34, $3a, $44, $3a, $30, $3a, $34, $3a, $2c, $3a, $2a, $3a, $2c, $3a, $44
	db $3a, $30, $3a, $34, $3a, $2c, $3a, $2a, $3a, $2c, $34, $2c, $26, $3e, $38, $32
	db $38, $2a, $38, $32, $38, $a3, $34, $42, $2a, $a2, $34, $3a, $42, $3a, $30, $3a
	db $2e, $34, $26, $34, $2e, $34, $a8, $30, $a2, $32, $38, $2a, $38, $32, $38, $a8
	db $34, $a3, $34, $2a, $24, $1c, $20, $24, $2c, $30, $34, $a8, $26, $00

;@ path: sound/music/songs
Song05Sq2::
	dw Song05Pat3, Song05Pat3, Song05Pat4, $FFFF, Song05Sq2

;@ path: sound/music/songs
Song05Sq1::
	dw Song05Pat1, Song05Pat1, Song05Pat2, $FFFF, Song05Sq1

;@ path: sound/music/songs
Song05Wave::
	dw Song05Pat5, Song05Pat5, Song05Pat6, Song05Pat6, $FFFF, Song05Wave

;@ path: sound/music/songs
Song05Noise::
	dw Song05Pat7, $FFFF, Song05Noise

;@ path: sound/music/songs
Song05Pat3::
	db $9d, $84, $00, $81, $a3, $52, $a2, $48, $4a, $a3, $4e, $a2, $4a, $48, $a3, $44
	db $a2, $44, $4a, $a3, $52, $a2, $4e, $4a, $a7, $48, $a2, $4a, $a3, $4e, $52, $a3
	db $4a, $44, $44, $01, $a2, $01, $a3, $4e, $a2, $54, $a3, $5c, $a2, $58, $54, $a7
	db $52, $a2, $4a, $a3, $52, $a2, $4e, $4a, $a3, $48, $a2, $48, $4a, $a3, $4e, $52
	db $a3, $4a, $44, $44, $01, $00

;@ path: sound/music/songs
Song05Pat4::
	db $9d, $50, $00, $81, $a4, $3a, $32, $36, $30, $a4, $32, $2c, $a8, $2a, $a3, $01
	db $a4, $3a, $32, $36, $30, $a3, $32, $3a, $a4, $44, $42, $01, $00

;@ path: sound/music/songs
Song05Pat1::
	db $9d, $43, $00, $81, $a3, $48, $a2, $42, $44, $48, $a1, $52, $4e, $a2, $44, $42
	db $a7, $3a, $a2, $44, $4a, $01, $a2, $48, $44, $a1, $42, $42, $a2, $3a, $42, $44
	db $a3, $48, $4a, $a3, $44, $3a, $3a, $01, $a2, $1e, $a3, $3c, $a2, $44, $4a, $a1
	db $4a, $4a, $a2, $48, $44, $a7, $40, $a2, $3a, $40, $a1, $44, $40, $a2, $3c, $3a
	db $42, $3a, $42, $44, $48, $42, $4a, $42, $a1, $44, $4a, $3a, $01, $a3, $3a, $3a
	db $01, $00

;@ path: sound/music/songs
Song05Pat2::
	db $9d, $30, $00, $81, $a4, $32, $2c, $30, $2a, $2c, $22, $a4, $22, $a3, $30, $01
	db $a4, $32, $2c, $30, $2a, $a3, $2c, $32, $a4, $3a, $36, $01, $00

;@ path: sound/music/songs
Song05Pat5::
	db $9d, $c9, $6e, $20, $a2, $22, $3a, $22, $3a, $22, $3a, $22, $3a, $2c, $44, $2c
	db $44, $2c, $44, $2c, $44, $2a, $42, $2a, $42, $22, $3a, $22, $3a, $2c, $44, $2c
	db $44, $2c, $44, $30, $32, $36, $1e, $01, $1e, $01, $1e, $2c, $24, $1a, $32, $01
	db $32, $1a, $28, $28, $01, $30, $48, $01, $48, $01, $3a, $01, $42, $2c, $3a, $2c
	db $3a, $a3, $2c, $01, $00

;@ path: sound/music/songs
Song05Pat6::
	db $9d, $c9, $6e, $20, $a2, $44, $52, $44, $52, $44, $52, $44, $52, $42, $52, $42
	db $52, $42, $52, $42, $52, $44, $52, $44, $52, $44, $52, $44, $52, $42, $52, $42
	db $52, $a4, $01, $00

;@ path: sound/music/songs
Song05Pat7::
	db $a2, $01, $06, $01, $06, $01, $a1, $06, $06, $a2, $01, $06, $01, $06, $01, $06
	db $01, $06, $06, $06, $00

;@ path: sound/music/songs
Song06Sq2::
	dw Song06Pat5, Song06Pat6, Song06Pat7, Song06Pat7, Song06Pat8, $FFFF, Song06Sq2

;@ path: sound/music/songs
Song06Sq1::
	dw Song06Pat1, Song06Pat2, Song06Pat3, Song06Pat3, Song06Pat4, $FFFF, Song06Sq1

;@ path: sound/music/songs
Song06Wave::
	dw Song06Pat9, Song06Pat10, Song06Pat11, Song06Pat11, Song06Pat11, Song06Pat11, Song06Pat11, Song06Pat11, Song06Pat12, Song06Pat13, Song06Pat13, Song06Pat13, Song06Pat14, Song06Pat15, Song06Pat15, Song06Pat16, Song06Pat16, Song06Pat17, Song06Pat17, Song06Pat16, Song06Pat18, $FFFF, Song06Wave

;@ path: sound/music/songs
Song06Noise::
	dw Song06Pat19, $FFFF, Song06Noise

;@ path: sound/music/songs
Song06Pat1::
	db $a5, $01, $00

;@ path: sound/music/songs
Song06Pat5::
	db $9d, $62, $00, $80, $a2, $3a, $a1, $3a, $3a, $a2, $30, $30, $3a, $a1, $3a, $3a
	db $a2, $30, $30, $00

;@ path: sound/music/songs
Song06Pat9::
	db $9d, $e9, $6e, $a0, $a2, $3a, $a1, $3a, $3a, $a2, $30, $30, $3a, $a1, $3a, $3a
	db $a2, $30, $30, $00

;@ path: sound/music/songs
Song06Pat19::
	db $a2, $06, $a1, $06, $06, $a2, $06, $06, $00

;@ path: sound/music/songs
Song06Pat2::
	db $a5, $01, $00

;@ path: sound/music/songs
Song06Pat6::
	db $9d, $32, $00, $80, $a2, $3a, $a1, $3a, $3a, $a2, $30, $30, $3a, $a1, $3a, $3a
	db $a2, $30, $30, $00

;@ path: sound/music/songs
Song06Pat10::
	db $9d, $e9, $6e, $a0, $a2, $3a, $a1, $3a, $3a, $a2, $30, $30, $3a, $a1, $3a, $3a
	db $a2, $30, $30, $00

;@ path: sound/music/songs
Song06Pat7::
	db $9d, $82, $00, $80, $a2, $3a, $48, $52, $50, $52, $a1, $48, $48, $a2, $4a, $44
	db $48, $a1, $40, $40, $a2, $44, $3e, $40, $a1, $3a, $3a, $a2, $3e, $38, $3a, $30
	db $32, $38, $3a, $30, $32, $3e, $00

;@ path: sound/music/songs
Song06Pat3::
	db $9d, $53, $00, $40, $a2, $30, $40, $40, $44, $40, $a1, $3e, $40, $a2, $44, $3e
	db $40, $a1, $38, $3a, $a2, $3e, $38, $3a, $a1, $2e, $30, $a2, $38, $30, $30, $28
	db $2c, $2c, $30, $28, $2c, $38, $00

;@ path: sound/music/songs
Song06Pat11::
	db $9d, $e9, $6e, $a0, $a2, $3a, $a1, $3a, $3a, $a2, $30, $30, $3a, $a1, $3a, $3a
	db $a2, $30, $30, $00

;@ path: sound/music/songs
Song06Pat8::
	db $a8, $3a, $a2, $3e, $38, $a8, $3a, $a3, $3e, $a2, $40, $a1, $40, $40, $a2, $44
	db $3e, $40, $a1, $40, $40, $a2, $44, $3e, $a8, $40, $a3, $44, $a2, $48, $a1, $48
	db $48, $a2, $4a, $44, $48, $a1, $48, $48, $a2, $4a, $44, $a8, $48, $a3, $4c, $a2
	db $4e, $a1, $4e, $4e, $a2, $4e, $4e, $52, $4e, $4e, $4c, $4e, $a1, $4e, $4e, $a2
	db $4e, $4e, $52, $4e, $4e, $4c, $4e, $a1, $4e, $4e, $a2, $4e, $4e, $4c, $a1, $4c
	db $4c, $a2, $4c, $4c, $4a, $a1, $4a, $4a, $a2, $4a, $44, $3e, $40, $44, $36, $44
	db $a1, $40, $40, $a2, $36, $a3, $40, $a1, $36, $3a, $a2, $36, $30, $44, $a1, $40
	db $40, $a2, $36, $a3, $40, $a1, $36, $3a, $a2, $36, $2e, $a5, $36, $a8, $01, $a3
	db $38, $00

;@ path: sound/music/songs
Song06Pat4::
	db $a8, $30, $a2, $30, $30, $a8, $30, $a3, $36, $a5, $01, $a8, $01, $a3, $3e, $a2
	db $40, $a1, $40, $40, $a2, $44, $3e, $40, $a1, $40, $40, $a2, $44, $3e, $a8, $36
	db $a3, $3a, $a2, $3e, $a1, $40, $44, $a2, $3e, $44, $48, $48, $48, $3a, $3e, $a1
	db $40, $44, $a2, $3e, $44, $46, $46, $46, $3a, $3e, $a1, $40, $44, $a2, $3e, $44
	db $3a, $a1, $3e, $40, $a2, $3a, $40, $3a, $a1, $3e, $40, $a2, $3e, $3e, $2c, $3a
	db $3e, $26, $30, $a1, $30, $30, $a2, $30, $a3, $30, $a1, $30, $34, $a2, $30, $28
	db $2e, $a1, $2e, $2e, $a2, $2e, $a3, $2e, $a1, $2e, $32, $a2, $2e, $28, $a5, $26
	db $a8, $01, $a3, $2c, $00

;@ path: sound/music/songs
Song06Pat12::
	db $a2, $3a, $a1, $3a, $3a, $a2, $32, $2c, $3a, $a1, $3a, $3a, $a2, $38, $30, $3a
	db $a1, $3a, $3a, $a2, $32, $2c, $3a, $a1, $3a, $3a, $a2, $2c, $1e, $00

;@ path: sound/music/songs
Song06Pat13::
	db $a2, $28, $a1, $40, $28, $a2, $1e, $36, $28, $a1, $40, $28, $a2, $1e, $36, $00

;@ path: sound/music/songs
Song06Pat14::
	db $a2, $28, $a1, $40, $28, $a2, $1e, $36, $28, $a1, $40, $28, $a2, $2c, $44, $00

;@ path: sound/music/songs
Song06Pat15::
	db $a2, $1e, $a1, $36, $1e, $a2, $1e, $36, $28, $a1, $40, $28, $a2, $28, $40, $00

;@ path: sound/music/songs
Song06Pat16::
	db $a2, $1e, $a1, $36, $1e, $a2, $1e, $36, $1e, $a1, $36, $1e, $a2, $1e, $36, $00

;@ path: sound/music/songs
Song06Pat17::
	db $a2, $22, $a1, $3a, $22, $a2, $22, $3a, $22, $a1, $3a, $22, $a2, $22, $3a, $00

;@ path: sound/music/songs
Song06Pat18::
	db $a2, $1e, $a1, $36, $1e, $a2, $1e, $36, $1e, $a1, $36, $1e, $a2, $a4, $3e, $00

; (not referenced by any song)
	db $36, $3e, $44, $a4, $44

;@ path: sound/music/songs
Song10Sq1::
	dw Song10Pat1
Song10Sq1Loop:
	dw Song10Pat2, $FFFF, Song10Sq1Loop

;@ path: sound/music/songs
Song10Sq2::
	dw Song10Pat3, $FFFF, Song10Sq2

;@ path: sound/music/songs
Song10Wave::
	dw Song10Pat4, $FFFF, Song10Wave

;@ path: sound/music/songs
Song10Pat1::
	db $9d, $20, $00, $81, $aa, $01, $00

;@ path: sound/music/songs
Song10Pat3::
	db $9d, $70, $00, $81
Song10Pat2:
	db $a2, $42, $32, $38, $42, $46, $34, $3c, $46, $4a, $38, $42, $4a, $4c, $3c, $42
	db $4c, $46, $34, $3c, $46, $40, $2e, $34, $40, $00

;@ path: sound/music/songs
Song10Pat4::
	db $9d, $e9, $6e, $21, $a8, $42, $a3, $2a, $a8, $42, $a3, $2a, $a8, $42, $a3, $2a
	db $00

;@ path: sound/music/songs
Song11Sq1::
	dw Song11Pat1
Song11Sq1Loop:
	dw Song11Pat2, $FFFF, Song11Sq1Loop

;@ path: sound/music/songs
Song11Sq2::
	dw Song11Pat3, $FFFF, Song11Sq2

;@ path: sound/music/songs
Song11Wave::
	dw Song11Pat4, $FFFF, Song11Wave

;@ path: sound/music/songs
Song11Pat1::
	db $9d, $20, $00, $81, $aa, $01, $00

;@ path: sound/music/songs
Song11Pat3::
	db $9d, $70, $00, $81
Song11Pat2:
	db $a2, $4c, $42, $50, $42, $54, $42, $50, $42, $56, $42, $54, $42, $50, $42, $54
	db $42, $4c, $42, $50, $42, $54, $42, $50, $42, $56, $42, $54, $42, $50, $42, $54
	db $42, $5a, $46, $56, $46, $54, $46, $50, $46, $4e, $46, $50, $46, $54, $46, $50
	db $46, $50, $3e, $4c, $3e, $4c, $3e, $4a, $3e, $4a, $3e, $46, $3e, $4a, $3e, $50
	db $3e, $00

;@ path: sound/music/songs
Song11Pat4::
	db $9d, $e9, $6e, $21, $a5, $4c, $4a, $46, $42, $38, $3e, $42, $42, $00

;@ path: sound/music/songs
Song04Sq2::
	dw Song04Pat2, $0000

;@ path: sound/music/songs
Song04Sq1::
; (no end marker: the engine reads on into Song04Wave)
	dw Song04Pat1

;@ path: sound/music/songs
Song04Wave::
; (no end marker: the engine reads on into Song04Pat2)
	dw Song04Pat3

;@ path: sound/music/songs
Song04Pat2::
	db $9d, $b2, $00, $80, $a2, $60, $5c, $60, $5c, $60, $62, $60, $5c, $a4, $60, $00

;@ path: sound/music/songs
Song04Pat1::
; (no $00 at the end: the engine reads on into Song03Sq2)
	db $9d, $92, $00, $80, $a2, $52, $4e, $52, $4e, $52, $54, $52, $4e, $a4, $52
Song04Pat3:
	db $9d, $e9, $6e, $20, $a2, $62, $60, $62, $60, $62, $66, $62, $60, $a3, $62, $01

;@ path: sound/music/songs
Song03Sq2::
	dw Song03Pat4, Song03Pat5, Song03Pat5, $0000

;@ path: sound/music/songs
Song03Sq1::
; (no end marker: the engine reads on into Song03Wave)
	dw Song03Pat1, Song03Pat2, Song03Pat3

;@ path: sound/music/songs
Song03Wave::
; (no end marker: the engine reads on into Song03Noise)
	dw Song03Pat6, Song03Pat7, Song03Pat7, Song03Pat8, Song03Pat7, Song03Pat7, Song03Pat9, Song03Pat8, Song03Pat7, Song03Pat7, Song03Pat9, Song03Pat8, Song03Pat10, Song03Pat11, Song03Pat9, Song03Pat8, Song03Pat7

;@ path: sound/music/songs
Song03Noise::
; (no end marker: the engine reads on into Song03Pat4)
	dw Song03Pat12, Song03Pat12, Song03Pat13, Song03Pat13, Song03Pat13, Song03Pat13

;@ path: sound/music/songs
Song03Pat4::
	db $9d, $c3, $00, $80, $a2, $3c, $3e, $3c, $3e, $38, $50, $a3, $01, $a2, $3c, $3e
	db $3c, $3e, $38, $50, $a3, $01, $a2, $01, $48, $01, $46, $01, $42, $01, $46, $a1
	db $42, $46, $a2, $42, $42, $38, $a3, $3c, $01, $a2, $3e, $42, $3e, $42, $3c, $54
	db $a3, $01, $a2, $3e, $42, $3e, $42, $3c, $54, $a3, $01, $a2, $01, $56, $01, $54
	db $01, $54, $01, $50, $a2, $01, $a1, $50, $54, $a2, $50, $4e, $a3, $50, $01, $00

;@ path: sound/music/songs
Song03Pat1::
	db $9d, $74, $00, $80, $a2, $36, $38, $36, $38, $2e, $3e, $a3, $01, $a2, $36, $38
	db $36, $38, $2e, $3e, $a3, $01, $a2, $01, $36, $01, $36, $01, $32, $01, $36, $36
	db $32, $32, $30, $a3, $36, $01, $a2, $38, $3c, $38, $3c, $36, $4e, $a3, $01, $a2
	db $38, $3c, $38, $3c, $36, $4e, $a3, $01, $a2, $01, $50, $01, $4e, $01, $46, $01
	db $46, $a2, $01, $a1, $48, $4e, $a2, $48, $46, $a3, $40, $01, $00

;@ path: sound/music/songs
Song03Pat6::
	db $9d, $e9, $6e, $20, $a2, $48, $46, $48, $46, $3e, $20, $a3, $01, $a2, $48, $46
	db $48, $46, $3e, $20, $a3, $01, $a2, $2e, $3c, $2e, $24, $24, $24, $24, $3c, $2a
	db $3e, $2a, $3e, $a6, $2e, $a3, $01, $a1, $01, $a2, $48, $46, $48, $46, $2e, $2e
	db $a3, $01, $a2, $48, $46, $48, $46, $2e, $2e, $a3, $01, $a2, $2a, $3c, $2a, $3c
	db $2e, $3e, $2e, $3e, $2e, $42, $2e, $42, $a6, $38, $a3, $01, $a1, $01, $00

;@ path: sound/music/songs
Song03Pat12::
	db $a8, $01, $a2, $06, $0b, $a8, $01, $a2, $06, $0b, $a5, $01, $01, $00

;@ path: sound/music/songs
Song03Pat5::
	db $9d, $c5, $00, $80, $a1, $46, $4a, $a4, $46, $a2, $01, $a3, $50, $a8, $4a, $a3
	db $01, $a1, $42, $46, $a4, $42, $a2, $01, $a3, $4e, $a1, $4e, $50, $a4, $46, $a7
	db $01, $a1, $40, $46, $a4, $40, $a2, $01, $a3, $46, $a1, $46, $4a, $a4, $42, $a7
	db $01, $a1, $36, $38, $a4, $36, $a2, $01, $a3, $3c, $a7, $42, $a4, $40, $a2, $01
	db $00

;@ path: sound/music/songs
Song03Pat2::
	db $9d, $84, $00, $41, $a1, $40, $42, $a4, $40, $a2, $01, $a3, $40, $a8, $42, $a3
	db $01, $a1, $3c, $40, $a4, $3c, $a2, $01, $a3, $3c, $a1, $3c, $40, $a4, $40, $a7
	db $01, $a1, $36, $32, $a4, $2e, $a2, $01, $a3, $40, $a1, $36, $38, $a4, $32, $a7
	db $01, $a1, $2e, $32, $a4, $2e, $a2, $01, $a3, $2a, $a7, $30, $a4, $2e, $a2, $01
	db $00

;@ path: sound/music/songs
Song03Pat7::
	db $a2, $38, $38, $01, $38, $38, $38, $01, $38, $00

;@ path: sound/music/songs
Song03Pat8::
	db $2e, $2e, $01, $2e, $2e, $2e, $01, $2e, $00

;@ path: sound/music/songs
Song03Pat9::
	db $2a, $2a, $01, $2a, $2a, $2a, $01, $2a, $00

;@ path: sound/music/songs
Song03Pat10::
	db $a2, $38, $38, $01, $38, $36, $36, $01, $36, $00

;@ path: sound/music/songs
Song03Pat11::
	db $32, $32, $01, $32, $2e, $2e, $01, $2e, $00

;@ path: sound/music/songs
Song03Pat13::
	db $a2, $06, $0b, $01, $06, $06, $0b, $01, $06, $06, $0b, $01, $06, $06, $0b, $01
	db $06, $06, $0b, $01, $06, $06, $0b, $01, $06, $06, $0b, $01, $06, $01, $0b, $01
	db $0b, $00

;@ path: sound/music/songs
Song03Pat3::
	db $9d, $66, $00, $81, $a7, $58, $5a, $a3, $58, $a7, $5e, $a4, $5a, $a2, $01, $a7
	db $50, $54, $a3, $58, $a7, $5a, $a4, $58, $a2, $01, $a7, $50, $a3, $4e, $a7, $4e
	db $58, $54, $a3, $4a, $a7, $5a, $5e, $a3, $5a, $a7, $54, $a4, $50, $a2, $01, $00

;@ path: sound/music/songs
Song0FSq1::
	dw Song0FPat1, Song0FPat2, Song0FPat1, Song0FPat3, $0000

;@ path: sound/music/songs
Song0FSq2::
; (no end marker: the engine reads on into Song0FWave)
	dw Song0FPat4, Song0FPat5, Song0FPat4, Song0FPat6

;@ path: sound/music/songs
Song0FWave::
; (no end marker: the engine reads on into Song0FNoise)
	dw Song0FPat7, Song0FPat8, Song0FPat7, Song0FPat9

;@ path: sound/music/songs
Song0FNoise::
; (no end marker: the engine reads on into Song0FPat1)
	dw Song0FPat10, Song0FPat11, Song0FPat10, Song0FPat11

;@ path: sound/music/songs
Song0FPat1::
	db $9d, $d1, $00, $80, $a2, $5c, $a1, $5c, $5a, $a2, $5c, $5c, $56, $52, $4e, $56
	db $a2, $52, $a1, $52, $50, $a2, $52, $52, $4c, $48, $44, $a1, $4c, $52, $00

;@ path: sound/music/songs
Song0FPat4::
	db $9d, $b2, $00, $80, $a2, $52, $a1, $52, $52, $a2, $52, $a1, $52, $52, $a2, $44
	db $a1, $44, $44, $a2, $44, $01, $4c, $a1, $4c, $4c, $a2, $4c, $a1, $4c, $4c, $a2
	db $3a, $a1, $3a, $3a, $a2, $3a, $01, $00

;@ path: sound/music/songs
Song0FPat7::
	db $9d, $e9, $6e, $20, $a2, $5c, $a1, $5c, $5c, $a2, $5c, $a1, $5c, $5c, $a2, $4e
	db $a1, $52, $52, $a2, $56, $01, $a2, $5c, $a1, $5c, $5c, $a2, $5c, $a1, $5c, $5c
	db $a2, $44, $a1, $48, $48, $a2, $4c, $01, $00

;@ path: sound/music/songs
Song0FPat10::
	db $a2, $06, $a7, $01, $a2, $0b, $0b, $0b, $01, $a2, $06, $a7, $01, $a2, $0b, $0b
	db $0b, $01, $00

;@ path: sound/music/songs
Song0FPat2::
	db $a2, $48, $a1, $48, $52, $a2, $44, $a1, $44, $52, $a2, $42, $a1, $42, $52, $a2
	db $48, $a1, $48, $52, $a2, $4c, $a1, $4c, $52, $a2, $44, $a1, $44, $52, $a2, $48
	db $44, $a1, $48, $52, $56, $5a, $00

;@ path: sound/music/songs
Song0FPat5::
	db $3a, $a1, $3a, $3a, $a2, $3a, $a1, $3a, $3a, $a2, $3a, $a1, $3a, $3a, $a2, $3a
	db $a1, $3a, $3a, $a2, $3a, $a1, $3a, $3a, $a2, $3a, $a1, $3a, $3a, $a2, $36, $a1
	db $36, $36, $a2, $36, $01, $00

;@ path: sound/music/songs
Song0FPat8::
	db $48, $a1, $48, $48, $a2, $48, $a1, $48, $48, $a2, $48, $a1, $48, $48, $a2, $48
	db $a1, $48, $48, $a2, $44, $a1, $44, $44, $a2, $44, $a1, $44, $44, $a2, $42, $a1
	db $42, $42, $a2, $42, $01, $00

;@ path: sound/music/songs
Song0FPat11::
	db $a2, $01, $0b, $01, $0b, $01, $0b, $01, $0b, $01, $0b, $01, $0b, $01, $0b, $0b
	db $01, $00

;@ path: sound/music/songs
Song0FPat3::
	db $a2, $48, $a1, $48, $52, $a2, $44, $a1, $44, $52, $a2, $42, $a1, $42, $52, $a2
	db $48, $a1, $48, $52, $a2, $4c, $a1, $4c, $52, $a2, $48, $a1, $48, $52, $a2, $44
	db $52, $a3, $5c, $00

;@ path: sound/music/songs
Song0FPat6::
	db $3a, $a1, $3a, $3a, $a2, $3a, $a1, $3a, $3a, $a2, $3a, $a1, $3a, $3a, $a2, $3a
	db $a1, $3a, $3a, $a2, $3a, $a1, $3a, $3a, $a2, $3a, $a1, $3a, $3a, $a2, $01, $3a
	db $a3, $4c, $00

;@ path: sound/music/songs
Song0FPat9::
	db $48, $a1, $48, $48, $a2, $48, $a1, $48, $48, $a2, $48, $a1, $48, $48, $a2, $48
	db $a1, $48, $48, $a2, $44, $a1, $44, $44, $a2, $44, $a1, $44, $44, $a2, $01, $4c
	db $a3, $44, $00

;@ path: sound/music/songs
Song0ASq2::
	dw Song0APat1, $0000

;@ path: sound/music/songs
Song0APat1::
	db $9d, $c2, $00, $40, $a2, $5c, $a1, $5c, $5a, $a2, $5c, $5c, $56, $52, $4e, $56
	db $a2, $52, $a1, $52, $50, $a2, $52, $52, $4c, $48, $a1, $44, $42, $a2, $44, $a4
	db $01, $00

;@ path: sound/music/songs
Song0BSq2::
	dw Song0BPat1, $0000

;@ path: sound/music/songs
Song0BWave::
; (no end marker: the engine reads on into Song0BPat1)
	dw Song0BPat2

;@ path: sound/music/songs
Song0BPat1::
	db $9d, $c2, $00, $80, $a2, $5c, $a1, $5c, $5a, $a2, $5c, $5c, $56, $52, $4e, $56
	db $a2, $52, $a1, $52, $50, $a2, $52, $4c, $44, $52, $a3, $5c, $a4, $01, $00

;@ path: sound/music/songs
Song0BPat2::
; (no $00 at the end: the engine reads on into Song0CSq2)
	db $9d, $e9, $6e, $20, $a2, $5c, $a1, $5c, $5c, $a2, $5c, $a1, $5c, $5c, $a2, $4e
	db $52, $56, $01, $a2, $5c, $a1, $5c, $5c, $a2, $5c, $a1, $5c, $5c, $a2, $52, $4c
	db $44, $01, $a5, $01

;@ path: sound/music/songs
Song0CSq2::
	dw Song0CPat2, $0000

;@ path: sound/music/songs
Song0CSq1::
; (no end marker: the engine reads on into Song0CWave)
	dw Song0CPat1

;@ path: sound/music/songs
Song0CWave::
; (no end marker: the engine reads on into Song0CPat2)
	dw Song0CPat3

;@ path: sound/music/songs
Song0CPat2::
	db $9d, $c2, $00, $80, $a2, $5c, $a1, $5c, $5a, $a2, $5c, $5c, $56, $52, $4e, $56
	db $a2, $52, $a1, $52, $50, $a2, $52, $4c, $44, $52, $a3, $5c, $a4, $01, $00

;@ path: sound/music/songs
Song0CPat1::
	db $9d, $c2, $00, $40, $a2, $4e, $a1, $4e, $52, $a2, $56, $4e, $a3, $48, $48, $a2
	db $4c, $a1, $4c, $4a, $a2, $4c, $44, $34, $4c, $a3, $4c, $a5, $01, $00

;@ path: sound/music/songs
Song0CPat3::
	db $9d, $e9, $6e, $20, $a2, $5c, $a1, $5c, $5c, $a2, $5c, $a1, $5c, $5c, $a2, $4e
	db $52, $a1, $56, $56, $a2, $56, $a2, $5c, $a1, $5c, $5c, $a2, $5c, $a1, $5c, $5c
	db $a2, $52, $4c, $a1, $44, $44, $a2, $01, $a5, $01, $00

;@ path: sound/music/songs
Song0DSq1::
	dw Song0DPat1, $0000

;@ path: sound/music/songs
Song0DSq2::
; (no end marker: the engine reads on into Song0DWave)
	dw Song0DPat2

;@ path: sound/music/songs
Song0DWave::
; (no end marker: the engine reads on into Song0DNoise)
	dw Song0DPat3

;@ path: sound/music/songs
Song0DNoise::
; (no end marker: the engine reads on into Song0DPat1)
	dw Song0DPat4

;@ path: sound/music/songs
Song0DPat1::
	db $9d, $c2, $00, $80, $a2, $5c, $a1, $5c, $5a, $a2, $5c, $5c, $56, $52, $4e, $56
	db $a2, $52, $a1, $52, $50, $a2, $52, $4c, $44, $52, $a3, $5c, $a4, $01, $00

;@ path: sound/music/songs
Song0DPat2::
; (no $00 at the end: the engine reads on into Song0ESq1)
	db $9d, $b2, $00, $80, $a2, $4e, $a1, $4e, $52, $a2, $56, $4e, $a3, $48, $48, $a2
	db $4c, $a1, $4c, $4a, $a2, $4c, $44, $34, $4c, $a3, $4c, $a5, $01
Song0DPat3:
	db $9d, $e9, $6e, $20, $a2, $5c, $a1, $5c, $5c, $a2, $5c, $a1, $5c, $5c, $4e, $56
	db $5c, $56, $4e, $44, $3e, $44, $a2, $5c, $a1, $5c, $5c, $a2, $5c, $a1, $5c, $5c
	db $52, $4c, $44, $4c, $5c, $01, $a2, $01, $a5, $01
Song0DPat4:
	db $a2, $0b, $0b, $0b, $0b, $a2, $0b, $0b, $0b, $01, $a2, $0b, $0b, $0b, $0b, $a2
	db $0b, $0b, $0b, $01, $a5, $01

;@ path: sound/music/songs
Song0ESq1::
	dw Song0EPat1, Song0EPat2, $0000

;@ path: sound/music/songs
Song0ESq2::
; (no end marker: the engine reads on into Song0EWave)
	dw Song0EPat3, Song0EPat4

;@ path: sound/music/songs
Song0EWave::
; (no end marker: the engine reads on into Song0ENoise)
	dw Song0EPat5, Song0EPat6

;@ path: sound/music/songs
Song0ENoise::
; (no end marker: the engine reads on into Song0EPat1)
	dw Song0EPat7, Song0EPat8

;@ path: sound/music/songs
Song0EPat1::
	db $9d, $d1, $00, $80, $a2, $5c, $a1, $5c, $5a, $a2, $5c, $5c, $56, $52, $4e, $56
	db $a2, $52, $a1, $52, $50, $a2, $52, $52, $4c, $48, $44, $a1, $4c, $52, $00

;@ path: sound/music/songs
Song0EPat3::
	db $a2, $52, $a7, $01, $a2, $44, $44, $44, $01, $4c, $a7, $01, $a2, $3a, $3a, $3a
	db $01, $00

;@ path: sound/music/songs
Song0EPat5::
	db $a2, $5c, $a7, $01, $a2, $4e, $52, $56, $01, $a2, $5c, $a7, $01, $a2, $44, $48
	db $4c, $01, $00

;@ path: sound/music/songs
Song0EPat7::
	db $a2, $06, $a7, $01, $a2, $0b, $0b, $0b, $01, $a2, $06, $a7, $01, $a2, $0b, $0b
	db $0b, $01, $00

;@ path: sound/music/songs
Song0EPat2::
	db $a2, $48, $a1, $48, $52, $a2, $44, $a1, $44, $52, $a2, $42, $a1, $42, $52, $a2
	db $48, $a1, $48, $52, $a2, $4c, $a1, $4c, $52, $a2, $48, $a1, $48, $52, $a2, $5c
	db $52, $a3, $5c, $00

;@ path: sound/music/songs
Song0EPat4::
; (no $00 at the end: the engine reads on into Song09Sq2)
	db $01, $3a, $01, $3a, $01, $3a, $01, $3a, $01, $3a, $01, $3a, $01, $3a, $a3, $34
Song0EPat6:
	db $01, $48, $01, $48, $01, $48, $01, $48, $01, $44, $01, $44, $01, $4c, $a3, $44
Song0EPat8:
	db $a2, $01, $0b, $01, $0b, $01, $0b, $01, $0b, $01, $0b, $01, $0b, $a2, $01, $0b
	db $0b, $01

;@ path: sound/music/songs
Song09Sq2::
	dw Song09Pat2, $0000

;@ path: sound/music/songs
Song09Sq1::
; (no end marker: the engine reads on into Song09Wave)
	dw Song09Pat1

;@ path: sound/music/songs
Song09Wave::
; (no end marker: the engine reads on into Song09Noise)
	dw Song09Pat3

;@ path: sound/music/songs
Song09Noise::
; (no end marker: the engine reads on into Song09Pat2)
	dw Song09Pat4

;@ path: sound/music/songs
Song09Pat2::
	db $9d, $b3, $00, $80, $a6, $52, $a1, $50, $a6, $52, $a1, $50, $a6, $52, $a1, $48
	db $a3, $01, $a6, $4c, $a1, $4a, $a6, $4c, $a1, $4a, $a6, $4c, $a1, $42, $a3, $01
	db $a6, $3e, $a1, $42, $a6, $44, $a1, $48, $a6, $4c, $a1, $50, $a6, $52, $a1, $56
	db $a6, $52, $a1, $6a, $00

;@ path: sound/music/songs
Song09Pat1::
; (no $00 at the end: the engine reads on into Song01Sq1)
	db $9d, $93, $00, $c0, $a6, $42, $a1, $40, $a6, $42, $a1, $40, $a6, $42, $a1, $42
	db $a3, $01, $a6, $3a, $a1, $38, $a6, $3a, $a1, $38, $a6, $3a, $a1, $3a, $a3, $01
	db $a6, $38, $a1, $38, $a6, $3a, $a1, $3e, $a6, $42, $a1, $44, $a6, $48, $a1, $4c
	db $a6, $42, $a1, $42
Song09Pat3:
	db $9d, $e9, $6e, $a0, $a6, $48, $a1, $46, $a6, $48, $a1, $46, $a6, $48, $a1, $52
	db $a3, $01, $a6, $44, $a1, $42, $a6, $44, $a1, $42, $a6, $44, $a1, $4c, $a3, $01
	db $a6, $48, $a1, $3a, $a6, $3e, $a1, $42, $a6, $44, $a1, $48, $a6, $4c, $a1, $50
	db $a6, $52, $a1, $3a
Song09Pat4:
	db $a6, $0b, $a1, $06, $a6, $0b, $a1, $06, $a6, $0b, $a1, $06, $a3, $01, $a6, $0b
	db $a1, $06, $a6, $0b, $a1, $06, $a6, $0b, $a1, $06, $a3, $01, $a6, $0b, $a1, $06
	db $a6, $0b, $a1, $06, $a6, $0b, $a1, $06, $a3, $01, $a6, $0b, $a1, $06

;@ path: sound/music/songs
Song01Sq1::
	dw Song01Pat1, $FFFF, Song01Sq1Loop

;@ path: sound/music/songs
Song01Sq2::
	dw Song01Pat2
Song01Sq1Loop:
	dw Song01Pat3
Song01Sq2Loop:
	dw Song01Pat4, Song01Pat5, Song01Pat4, Song01Pat6, Song01Pat7, $FFFF, Song01Sq2Loop

;@ path: sound/music/songs
Song01Wave::
	dw Song01Pat8
Song01WaveLoop:
	dw Song01Pat9, Song01Pat10, Song01Pat9, Song01Pat11, Song01Pat12, $FFFF, Song01WaveLoop

;@ path: sound/music/songs
Song01Noise::
	dw Song01Pat13
Song01NoiseLoop:
	dw Song01Pat14, $FFFF, Song01NoiseLoop

;@ path: sound/music/songs
Song01Pat2::
	db $9d, $60, $00, $81, $00

;@ path: sound/music/songs
Song01Pat1::
	db $9d, $20, $00, $81, $aa, $01, $00

;@ path: sound/music/songs
Song01Pat3::
	db $a3, $01, $50, $54, $58, $00

;@ path: sound/music/songs
Song01Pat8::
	db $a5, $01, $00

;@ path: sound/music/songs
Song01Pat13::
	db $a5, $01, $00

;@ path: sound/music/songs
Song01Pat14::
	db $a3, $01, $06, $01, $06, $01, $a2, $06, $06, $a3, $01, $06, $a3, $01, $06, $01
	db $06, $01, $a2, $06, $06, $01, $01, $06, $06, $00

;@ path: sound/music/songs
Song01Pat4::
	db $a7, $5a, $a2, $5e, $a7, $5a, $a2, $58, $a7, $58, $a2, $54, $a7, $58, $a2, $54
	db $00

;@ path: sound/music/songs
Song01Pat9::
	db $9d, $c9, $6e, $20, $a2, $5a, $62, $68, $70, $5a, $62, $68, $70, $5a, $64, $66
	db $6c, $5a, $64, $66, $6c, $00

;@ path: sound/music/songs
Song01Pat5::
	db $a7, $54, $a2, $50, $a7, $54, $a2, $50, $a7, $50, $a2, $4c, $a7, $4a, $a2, $50
	db $00

;@ path: sound/music/songs
Song01Pat10::
	db $58, $5e, $64, $6c, $58, $5e, $64, $6c, $50, $54, $58, $5e, $50, $58, $5e, $64
	db $00

;@ path: sound/music/songs
Song01Pat6::
	db $a7, $54, $a2, $50, $a7, $54, $a2, $50, $a7, $50, $a2, $4c, $a7, $4a, $a2, $46
	db $00

;@ path: sound/music/songs
Song01Pat11::
	db $58, $5e, $64, $6c, $58, $5e, $64, $6c, $50, $54, $58, $5e, $50, $58, $5e, $64
	db $00

;@ path: sound/music/songs
Song01Pat7::
	db $a7, $4a, $a2, $4c, $a7, $4a, $a2, $46, $a7, $46, $a2, $44, $a7, $46, $a2, $4a
	db $a7, $4c, $a2, $50, $a7, $4c, $a2, $4a, $a7, $4a, $a2, $46, $a7, $4a, $a2, $4c
	db $a7, $50, $a2, $4e, $a7, $50, $a2, $52, $a7, $58, $a2, $54, $a7, $5a, $a2, $54
	db $a7, $52, $a2, $50, $a7, $4c, $a2, $4a, $a2, $42, $38, $3c, $4a, $a3, $42, $01
	db $00

;@ path: sound/music/songs
Song01Pat12::
	db $4a, $52, $58, $5e, $4a, $58, $5e, $62, $54, $62, $68, $6c, $54, $62, $68, $6c
	db $46, $4c, $54, $5e, $46, $4c, $54, $5a, $50, $58, $5e, $64, $50, $5e, $64, $6c
	db $4a, $50, $58, $5e, $4a, $58, $5e, $62, $4e, $54, $5a, $62, $4e, $54, $5a, $66
	db $50, $58, $5e, $64, $50, $5e, $64, $68, $a8, $5a, $a3, $01, $00

;@ path: sound/music/songs
Song02Sq2::
	dw Song02Pat2, $0000

;@ path: sound/music/songs
Song02Sq1::
; (no end marker: the engine reads on into Song02Wave)
	dw Song02Pat1

;@ path: sound/music/songs
Song02Wave::
; (no end marker: the engine reads on into Song02Noise)
	dw Song02Pat3

;@ path: sound/music/songs
Song02Noise::
; (no end marker: the engine reads on into Song02Pat2)
	dw Song02Pat4

;@ path: sound/music/songs
Song02Pat2::
	db $9d, $b1, $00, $80, $a7, $01, $a1, $5e, $5e, $a6, $68, $a1, $5e, $a4, $68, $00

;@ path: sound/music/songs
Song02Pat1::
; (no $00 at the end: the engine reads on into Song08Sq2)
	db $9d, $91, $00, $80, $a7, $01, $a1, $54, $54, $a6, $5e, $a1, $58, $a4, $5e
Song02Pat3:
	db $9d, $e9, $6e, $20, $a7, $01, $a1, $4e, $4e, $a6, $58, $a1, $50, $a3, $58, $01
Song02Pat4:
	db $a7, $01, $a1, $06, $06, $a6, $0b, $a1, $06, $a0, $06, $06, $06, $06, $06, $06
	db $06, $06, $a3, $01

;@ path: sound/music/songs
Song08Sq2::
	dw Song08Pat4, Song08Pat5, Song08Pat4, Song08Pat6, $FFFF, Song08Sq2

;@ path: sound/music/songs
Song08Sq1::
	dw Song08Pat1, Song08Pat2, Song08Pat1, Song08Pat3, $FFFF, Song08Sq1

;@ path: sound/music/songs
Song08Wave::
	dw Song08Pat7, Song08Pat8, Song08Pat7, Song08Pat9, $FFFF, Song08Wave

;@ path: sound/music/songs
Song08Noise::
	dw Song08Pat10, $FFFF, Song08Noise

;@ path: sound/music/songs
Song08Pat4::
	db $9d, $82, $00, $80, $a2, $54, $a1, $54, $54, $54, $4a, $46, $4a, $a2, $54, $a1
	db $54, $54, $54, $58, $5c, $58, $a2, $54, $a1, $54, $54, $58, $54, $52, $54, $a1
	db $58, $5c, $58, $5c, $a2, $58, $a1, $56, $58, $00

;@ path: sound/music/songs
Song08Pat1::
	db $9d, $62, $00, $80, $a2, $01, $44, $01, $40, $01, $44, $01, $46, $01, $44, $01
	db $44, $01, $40, $01, $40, $00

;@ path: sound/music/songs
Song08Pat7::
	db $9d, $e9, $6e, $20, $a2, $54, $54, $4a, $52, $54, $54, $4a, $58, $54, $54, $52
	db $54, $4e, $54, $4a, $52, $00

;@ path: sound/music/songs
Song08Pat10::
	db $a2, $06, $0b, $06, $0b, $06, $0b, $06, $0b, $06, $0b, $06, $0b, $06, $a1, $0b
	db $0b, $06, $a2, $0b, $a1, $06, $00

;@ path: sound/music/songs
Song08Pat5::
	db $a2, $5e, $a1, $5e, $5e, $5e, $54, $50, $54, $a2, $5e, $a1, $5e, $5e, $5e, $62
	db $66, $62, $a2, $5e, $a1, $5e, $5c, $a2, $58, $a1, $58, $54, $a1, $52, $54, $52
	db $54, $a2, $52, $a1, $4e, $52, $00

;@ path: sound/music/songs
Song08Pat2::
	db $a2, $01, $46, $01, $4a, $01, $46, $01, $4a, $01, $46, $01, $46, $01, $46, $01
	db $46, $00

;@ path: sound/music/songs
Song08Pat8::
	db $a2, $46, $54, $54, $54, $46, $54, $54, $54, $46, $54, $52, $58, $44, $52, $4a
	db $58, $00

;@ path: sound/music/songs
Song08Pat6::
	db $a2, $62, $a1, $62, $62, $62, $5e, $5a, $5e, $a2, $62, $a1, $62, $62, $62, $5e
	db $5a, $5e, $a2, $62, $a1, $4a, $4e, $a2, $52, $a1, $4a, $5c, $a3, $58, $a1, $54
	db $a6, $6c, $00

;@ path: sound/music/songs
Song08Pat3::
	db $a2, $01, $4a, $01, $4a, $01, $4a, $01, $4a, $01, $a1, $46, $46, $a2, $46, $a1
	db $46, $46, $a3, $46, $a2, $44, $01, $00

;@ path: sound/music/songs
Song08Pat9::
	db $a2, $42, $5a, $50, $5a, $42, $5a, $50, $5a, $4a, $a1, $52, $52, $a2, $52, $a1
	db $52, $52, $a3, $52, $a2, $54, $01, $00

; (not referenced by any song)
	db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
	db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
	db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

;@ def UpdateSound()
;@ path: sound/api
;@ Fixed entry point at the end of the bank, called once per frame from
;@ the VBlank handler: runs the sound engine.
;@ test: skip runs the whole sound engine on random state
;@ sig: 8c62c296
UpdateSound::
;> return SoundEngine()
	jp SoundEngine


;@ def InitSound()
;@ path: sound/api
;@ Fixed entry point at the end of the bank: stops all sound.
;@ sig: 6495f545
InitSound::
;> return SoundInit()
	jp SoundInit

	db $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
