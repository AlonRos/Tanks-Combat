.model flat, stdcall
.stack 100h

option casemap:none

include <\masm32\include\windows.inc>
include <\masm32\include\Ws2_32.inc>
include <\masm32\include\kernel32.inc>

READY_MSG equ 1
START_GAME_MSG equ 2
SWAP_LOCATIONS_MSG equ 3
END_ROUND_MSG equ 5

WINDOW_WIDTH equ 700
WINDOW_HEIGHT equ 700
FRAME_DEPTH equ 40

TPlayer struct
	
	ready BOOLEAN FALSE
	sock SOCKET ?
	opponentSock SOCKET ?

TPlayer ends

acceptClientsParams struct
	
	serverSocket SOCKET ?
	playersPTR dword ?
	receiveFromClientArgsPTR dword ?

acceptClientsParams ends

receiveFromClientParams struct
	
	currentPlayerPTR dword ?
	amountReadyPTR dword ?
	playersPTR dword ?
	wallsPTR dword ?
	gameOverPTR dword ?
	numberOfWalls dword ?
	maxBulletsInAnyMoment byte ?
	bulletLife dword ?

receiveFromClientParams ends

.data?
wsaData WSADATA{}
serverSocket SOCKET ?

.const
portToBind dw 13568
ipToBind db "0.0.0.0", 0

walls RECT {FRAME_DEPTH+50, FRAME_DEPTH+50, FRAME_DEPTH+300, FRAME_DEPTH+200}
RECT {WINDOW_WIDTH-(FRAME_DEPTH+50)-150, FRAME_DEPTH+50, WINDOW_WIDTH-(FRAME_DEPTH+50), FRAME_DEPTH+300}
RECT {FRAME_DEPTH+50, WINDOW_WIDTH-(FRAME_DEPTH+50)-250, FRAME_DEPTH+50+150, WINDOW_WIDTH-(FRAME_DEPTH+50)}
RECT {WINDOW_WIDTH-(FRAME_DEPTH+50)-250, WINDOW_WIDTH-(FRAME_DEPTH+50)-150, WINDOW_WIDTH-(FRAME_DEPTH+50), WINDOW_WIDTH-(FRAME_DEPTH+50)}
RECT {0, 0, WINDOW_WIDTH-1, FRAME_DEPTH-1}, {0, FRAME_DEPTH-1, FRAME_DEPTH-1, WINDOW_HEIGHT-1}, {WINDOW_WIDTH-FRAME_DEPTH, FRAME_DEPTH-1, WINDOW_WIDTH-1, WINDOW_HEIGHT-1}, {FRAME_DEPTH, WINDOW_HEIGHT-FRAME_DEPTH, WINDOW_WIDTH-FRAME_DEPTH-1, WINDOW_HEIGHT-1}
numberOfWalls dword 8
maxBulletsInAnyMoment byte 7
bulletLife dword 7000

.data
players TPlayer 2 dup({})
amountReady db 0

gameOver BOOLEAN FALSE

receiveFromClientArgs receiveFromClientParams{?, offset amountReady, offset players, offset walls, offset gameOver}
acceptClientsArgs acceptClientsParams{?, offset players, offset receiveFromClientArgs}

.code
StructCopy proc structSize:dword, s1:ptr byte, s2:ptr byte
	push ecx
	push eax
	push esi
	push edi

	mov ecx, 0
	mov esi, [s2]
	mov edi, [s1]
	loop_StructCopy:
	mov al, byte ptr [esi+ecx]
	mov byte ptr [edi+ecx], al

	inc ecx
	cmp ecx, [structSize]
	jnz loop_StructCopy

	pop edi
	pop esi
	pop eax
	pop ecx
ret
StructCopy endp


sendAll proc playersPTR:dword, bufferPTR:ptr byte, bufferLength:dword
	push eax
	push ecx
	push edx
	push esi

	mov esi, [playersPTR]
	assume esi:ptr TPlayer
	invoke send, [[esi].sock], [bufferPTR], [bufferLength], 0
	invoke send, [[esi].opponentSock], [bufferPTR], [bufferLength], 0

	pop esi
	pop edx
	pop ecx
	pop eax
ret
sendAll endp

createStartGameMsg proc bufPTR:ptr byte, wallsPTR:ptr RECT, amountWalls:dword, maxBullets:byte, bulletLifeDuration:dword
	push edi
	push edx

	mov edi, [bufPTR]

	mov byte ptr [edi], START_GAME_MSG

	mov eax, [amountWalls]
	mov [edi+1], eax

	mov eax, [bulletLifeDuration]
	mov [edi+5], eax

	mov al, [maxBullets]
	mov [edi+9], al

	mov eax, sizeof RECT
	mul [amountWalls]
	mov edx, eax

	add eax, 10
	push eax
	invoke StructCopy, edx, addr [edi+10], [wallsPTR]
	pop eax

	pop edx
	pop edi
ret
createStartGameMsg endp

receiveFromClient proc argsPTR:ptr receiveFromClientParams
	local buf[1024]:byte
	push eax
	push ecx
	push ebx
	push edx
	push esi

	mov ebx, [argsPTR]
	assume ebx:ptr receiveFromClientParams

	mov esi, [[ebx].currentPlayerPTR]
	assume esi:ptr TPlayer
	.while BOOLEAN ptr [[esi].ready] == FALSE
		invoke recv, [[esi].sock], addr buf, lengthof buf, 0
		.if byte ptr [buf] == READY_MSG
			mov BOOLEAN ptr [[esi].ready], TRUE
			mov edx, offset amountReady
			inc byte ptr [edx]
			.if byte ptr [edx] == 2
				mov byte ptr [buf], SWAP_LOCATIONS_MSG
				invoke send, [[esi].sock], addr buf, 1, 0

				invoke createStartGameMsg, addr buf, [[ebx].wallsPTR], [[ebx].numberOfWalls], [[ebx].maxBulletsInAnyMoment], [[ebx].bulletLife]
				invoke sendAll, [[ebx].playersPTR], addr buf, eax

			.endif
		.endif
	.endw

	.while TRUE
		invoke recv, [[esi].sock], addr buf, lengthof buf, 0 
		invoke send, [[esi].opponentSock], addr buf, eax, 0

		.if byte ptr [buf] == END_ROUND_MSG
			mov ecx, [[ebx].gameOverPTR]
			mov BOOLEAN ptr [ecx], TRUE
			.break
		.endif
	.endw

	pop esi
	pop edx
	pop ecx
	pop ebx
	pop eax
ret
receiveFromClient endp

acceptClients proc argsPTR:ptr acceptClientsParams
	push eax
	push ebx
	push ecx
	push edx
	push esi
	push edi

	mov edi, [argsPTR]
	assume edi:ptr acceptClientsParams

	mov esi, [[edi].playersPTR]
	assume esi:ptr TPlayer
	mov bl, 0 ; amount accepted
	.while bl < 2
		invoke accept, [[edi].serverSocket], NULL, NULL
		mov [[esi].sock], eax ; client accepted
		inc bl

		.if bl == 2
			mov edx, esi
			sub edx, sizeof TPlayer ; first player
			assume edx:ptr TPlayer

			mov eax, [[edx].sock]
			mov [[esi].opponentSock], eax

			mov eax, [[esi].sock]
			mov [[edx].opponentSock], eax
		.endif

		mov edx, [[edi].receiveFromClientArgsPTR]
		assume edx:ptr receiveFromClientParams
		mov [[edx].currentPlayerPTR], esi

		invoke CreateThread, NULL, NULL, [receiveFromClient], [[edi].receiveFromClientArgsPTR], 0, NULL
		add esi, sizeof TPlayer
	.endw

	pop edi
	pop esi
	pop edx
	pop ecx
	pop ebx
	pop eax
	

ret
acceptClients endp

_main proc
	local addressToBind:sockaddr_in

	mov eax, [numberOfWalls]
	mov [receiveFromClientArgs.numberOfWalls], eax

	mov al, [maxBulletsInAnyMoment]
	mov [receiveFromClientArgs.maxBulletsInAnyMoment], al

	mov eax, [bulletLife]
	mov [receiveFromClientArgs.bulletLife], eax

	invoke WSAStartup, 2, addr wsaData
    invoke socket, AF_INET, SOCK_STREAM, IPPROTO_TCP
	mov [serverSocket], eax

	mov addressToBind.sin_family, AF_INET
	
	invoke htons, [portToBind]
    mov [addressToBind.sin_port], ax
	
	invoke inet_addr, addr ipToBind
    mov [addressToBind.sin_addr], eax
    
    invoke bind, [serverSocket], addr addressToBind, sizeof addressToBind

	invoke listen, [serverSocket], SOMAXCONN
	
	mov eax, [serverSocket]
	mov [acceptClientsArgs.serverSocket], eax

	invoke CreateThread, NULL, NULL, [acceptClients], addr acceptClientsArgs, 0, NULL
	
	.while BOOLEAN ptr [gameOver] == FALSE
		invoke Sleep, 1000
	.endw

	invoke closesocket, [serverSocket]
    invoke WSACleanup
	invoke ExitProcess, 0
ret
_main endp
end _main