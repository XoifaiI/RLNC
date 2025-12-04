--!native
--!optimize 2
--!strict

local RLNC = require("@self/RLNC")
type RLNCError = RLNC.RLNCError

local RNG = Random.new()

-- 1. Define original data parameters
local OriginalDataLen = 1024 * 10 -- 10 KB
local PieceCount = 32 -- Data will be split into 32 pieces

local OriginalData = buffer.create(OriginalDataLen)
for I = 0, OriginalDataLen - 1 do
	buffer.writeu8(OriginalData, I, RNG:NextInteger(0, 255))
end

local OriginalDataCopy = buffer.create(OriginalDataLen)
buffer.copy(OriginalDataCopy, 0, OriginalData, 0, OriginalDataLen)

-- 2. Start the Encoder
local Encoder, EncoderError = RLNC.Encoder.New(OriginalData, PieceCount)
if EncoderError then
	error("Failed to create RLNC encoder: " .. RLNC.Error.Message(EncoderError :: RLNCError))
end
assert(Encoder)

print(string.format(
	"Initialized Encoder with %d bytes of data, split into %d pieces, each of %d bytes. Each coded piece will be of %d bytes",
	OriginalDataLen,
	PieceCount,
	Encoder:GetPieceByteLen(),
	Encoder:GetFullCodedPieceByteLen()
	))

local Overhead = (Encoder:GetFullCodedPieceByteLen() * PieceCount) / OriginalDataLen * 100 - 100
print(string.format("Overhead of encoding: %.2f%%", Overhead))

-- 3. Start the Decoder
print(string.format(
	"Initializing Decoder, expecting %d original pieces of %d bytes each",
	Encoder:GetPieceCount(),
	Encoder:GetPieceByteLen()
	))

local Decoder, DecoderError = RLNC.Decoder.New(Encoder:GetPieceByteLen(), Encoder:GetPieceCount())
if DecoderError then
	error("Failed to create RLNC decoder: " .. RLNC.Error.Message(DecoderError :: RLNCError))
end
assert(Decoder)

-- 4. Example of a sender generating initial coded pieces
local NumInitialCodedPieces = Encoder:GetPieceCount() // 2
print(string.format("\nSender generating %d initial coded pieces...", NumInitialCodedPieces))

local PiecesForRecoderLen = NumInitialCodedPieces * Encoder:GetFullCodedPieceByteLen()
local PiecesForRecoder = buffer.create(PiecesForRecoderLen)
local RecoderOffset = 0

for I = 1, NumInitialCodedPieces do
	local CodedPiece = Encoder:Code(RNG)
	buffer.copy(PiecesForRecoder, RecoderOffset, CodedPiece, 0, buffer.len(CodedPiece))
	RecoderOffset += buffer.len(CodedPiece)

	local DecodeError = Decoder:Decode(CodedPiece)

	if DecodeError == nil then
		print(string.format("  Decoded direct piece %d: Useful", I))
	elseif DecodeError == RLNC.Error.PieceNotUseful then
		print(string.format("  Decoded direct piece %d: Not useful", I))
	elseif DecodeError == RLNC.Error.ReceivedAllPieces then
		print(string.format("  Decoded direct piece %d: All pieces received, breakin", I))
		break
	else
		error("Unexpected error during direct decoding: " .. RLNC.Error.Message(DecodeError :: RLNCError))
	end
end

-- 5. Start the Recoder with same coded pieces which were already used for decoding
print(string.format("\Starting Recoder with %d bytes of received coded pieces", buffer.len(PiecesForRecoder)))

local Recoder, RecoderError = RLNC.Recoder.New(
	PiecesForRecoder,
	Encoder:GetFullCodedPieceByteLen(),
	Encoder:GetPieceCount()
)
if RecoderError then
	error("Failed to create RLNC recoder: " .. RLNC.Error.Message(RecoderError :: RLNCError))
end
assert(Recoder)

-- 6. Generate recoded pieces, all will be linearly dependent on original pieces
print("\nRecoder active. Generating recoded pieces (all will be useless since they're from same source)..")
local NumRecodedPiecesToSend = Encoder:GetPieceCount() * 2

for I = 1, NumRecodedPiecesToSend do
	if Decoder:IsAlreadyDecoded() then
		print("  All necessary pieces received via recoding")
		break
	end

	local RecodedPiece = Recoder:Recode(RNG)
	local DecodeError = Decoder:Decode(RecodedPiece)

	if DecodeError == nil then
		print(string.format("  Decoded recoded piece %d: Useful", I))
	elseif DecodeError == RLNC.Error.PieceNotUseful then
		print(string.format("  Decoded recoded piece %d: Not useful", I))
	elseif DecodeError == RLNC.Error.ReceivedAllPieces then
		print(string.format("  Decoded recoded piece %d: All pieces received, breaking", I))
		break
	else
		error("Unexpected error during recoded piece decoding: " .. RLNC.Error.Message(DecodeError :: RLNCError))
	end
end

-- 7. Generate NEW coded pieces for a new recoder
local PiecesForNewRecoderLen = NumInitialCodedPieces * Encoder:GetFullCodedPieceByteLen()
local PiecesForNewRecoder = buffer.create(PiecesForNewRecoderLen)
local NewRecoderOffset = 0

for _ = 1, NumInitialCodedPieces do
	local CodedPiece = Encoder:Code(RNG)
	buffer.copy(PiecesForNewRecoder, NewRecoderOffset, CodedPiece, 0, buffer.len(CodedPiece))
	NewRecoderOffset += buffer.len(CodedPiece)
end

print(string.format("\Starting a new Recoder with %d bytes of NEW coded pieces", buffer.len(PiecesForNewRecoder)))

local NewRecoder, NewRecoderError = RLNC.Recoder.New(
	PiecesForNewRecoder,
	Encoder:GetFullCodedPieceByteLen(),
	Encoder:GetPieceCount()
)
if NewRecoderError then
	error("Failed to create new RLNC recoder: " .. RLNC.Error.Message(NewRecoderError :: RLNCError))
end
assert(NewRecoder)

-- 8. Generate recoded pieces from NEW source - these should be useful
local NumNewRecodedPieces = NumInitialCodedPieces // 2
print(string.format("\nGenerating %d recoded pieces from new source...", NumNewRecodedPieces))

for I = 1, NumNewRecodedPieces do
	if Decoder:IsAlreadyDecoded() then
		print("  All necessary pieces received via recoding")
		break
	end

	local RecodedPiece = NewRecoder:Recode(RNG)
	local DecodeError = Decoder:Decode(RecodedPiece)

	if DecodeError == nil then
		print(string.format("  Decoded recoded piece %d: Useful", I))
	elseif DecodeError == RLNC.Error.PieceNotUseful then
		print(string.format("  Decoded recoded piece %d: Not useful", I))
	elseif DecodeError == RLNC.Error.ReceivedAllPieces then
		print(string.format("  Decoded recoded piece %d: All pieces received, breaking", I))
		break
	else
		error("Unexpected error during new recoded piece decoding: " .. RLNC.Error.Message(DecodeError :: RLNCError))
	end
end

-- 9. If not yet decoded, continue generating direct coded pieces
local DirectPieceCount = NumInitialCodedPieces
while not Decoder:IsAlreadyDecoded() do
	print(string.format("\nStill need more piece, generating direct piece %d from encoder..", DirectPieceCount + 1))
	local CodedPiece = Encoder:Code(RNG)
	local DecodeError = Decoder:Decode(CodedPiece)

	if DecodeError == nil then
		DirectPieceCount += 1
		print(string.format("  Decoded direct piece %d: Useful", DirectPieceCount))
	elseif DecodeError == RLNC.Error.PieceNotUseful then
		print(string.format("  Decoded direct piece %d: Not useful", DirectPieceCount + 1))
	elseif DecodeError == RLNC.Error.ReceivedAllPieces then
		print("  All pieces received via direct encoding")
		break
	else
		error("Unexpected error during direct decoding (post-recoding): " .. RLNC.Error.Message(DecodeError :: RLNCError))
	end
end

-- 10. Getting the decoded data
print("\nGetting decoded data...")
local DecodedData, DecodeDataError = Decoder:GetDecodedData()
if DecodeDataError then
	error("Failed to retrieve decoded data: " .. RLNC.Error.Message(DecodeDataError :: RLNCError))
end
assert(DecodedData)

-- 11. Verify that the decoded data matches the original data
local DecodedLen = buffer.len(DecodedData)
if DecodedLen ~= OriginalDataLen then
	error(string.format("Length mismatch! Original: %d, Decoded: %d", OriginalDataLen, DecodedLen))
end

for I = 0, OriginalDataLen - 1 do
	local OriginalByte = buffer.readu8(OriginalDataCopy, I)
	local DecodedByte = buffer.readu8(DecodedData, I)
	if OriginalByte ~= DecodedByte then
		error(string.format("Data mismatch at byte %d! Original: %d, Decoded: %d", I, OriginalByte, DecodedByte))
	end
end

print("\nRLNC example completed successfully, original data matches decoded data")
print(string.format("Total pieces received: %d", Decoder:GetReceivedPieceCount()))
print(string.format("Useful pieces: %d", Decoder:GetUsefulPieceCount()))