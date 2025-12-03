--[=[
	RLNCError: Error Types for Random Linear Network Coding
	
	Just errors, what more were you expecting?
--]=]

--!strict
--!optimize 2

export type RLNCError =
	| "CodingVectorLengthMismatch"
| "DataLengthMismatch"
| "PieceCountZero"
| "DataLengthZero"
| "PieceLengthZero"
| "NotEnoughPiecesToRecode"
| "PieceLengthTooShort"
| "PieceNotUseful"
| "ReceivedAllPieces"
| "NotAllPiecesReceivedYet"
| "InvalidDecodedDataFormat"
| "InvalidPieceLength"
| "InvalidOutputBuffer"

local MESSAGES: { [RLNCError]: string } = {
	CodingVectorLengthMismatch = "Coding vector length mismatch",
	DataLengthMismatch = "Data length mismatch",
	PieceCountZero = "Piece count is zero",
	DataLengthZero = "Data length is zero",
	PieceLengthZero = "Piece length is zero",
	NotEnoughPiecesToRecode = "Not enough pieces received to recode",
	PieceLengthTooShort = "Piece length is too short",
	PieceNotUseful = "Received piece is not useful",
	ReceivedAllPieces = "Received all pieces",
	NotAllPiecesReceivedYet = "Not all pieces are received yet",
	InvalidDecodedDataFormat = "Invalid decoded data format",
	InvalidPieceLength = "Invalid piece length",
	InvalidOutputBuffer = "Invalid output buffer",
}

local function Message(Error: RLNCError): string
	return MESSAGES[Error]
end

return {
	CodingVectorLengthMismatch = "CodingVectorLengthMismatch" :: RLNCError,
	DataLengthMismatch = "DataLengthMismatch" :: RLNCError,
	PieceCountZero = "PieceCountZero" :: RLNCError,
	DataLengthZero = "DataLengthZero" :: RLNCError,
	PieceLengthZero = "PieceLengthZero" :: RLNCError,
	NotEnoughPiecesToRecode = "NotEnoughPiecesToRecode" :: RLNCError,
	PieceLengthTooShort = "PieceLengthTooShort" :: RLNCError,
	PieceNotUseful = "PieceNotUseful" :: RLNCError,
	ReceivedAllPieces = "ReceivedAllPieces" :: RLNCError,
	NotAllPiecesReceivedYet = "NotAllPiecesReceivedYet" :: RLNCError,
	InvalidDecodedDataFormat = "InvalidDecodedDataFormat" :: RLNCError,
	InvalidPieceLength = "InvalidPieceLength" :: RLNCError,
	InvalidOutputBuffer = "InvalidOutputBuffer" :: RLNCError,

	Message = Message,
}