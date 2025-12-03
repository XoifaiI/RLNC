--[=[
	RLNCRecoder: Random Linear Network Coding Recoder
	
	Takes already coded pieces and recodes them using a new randomly sampled
	coding vector. Useful for distributing coded pieces more widely without
	needing to decode back to original data.
	
	A recoder acts as a new encoder operating on encoded source pieces.
	The output coding vector is done by multiplying the random recoding
	vector by the matrix of received coding vectors.
	
	Return type: Recoder constructor and methods
	
	Example usage:
		local RLNCRecoder = require(path.to.RLNCRecoder)
		
		local CodedPieces = buffer.create(NumPieces * FullCodedPieceLen)
		-- ... fill with received coded pieces ...
		
		local Recoder, Error = RLNCRecoder.New(CodedPieces, FullCodedPieceLen, NumPiecesCoded)
		
		if Recoder then
			local RecodedPiece = Recoder:Recode(Random.new())
		end
--]=]

--!strict
--!optimize 2
--!native

local GF256 = require("./GF256")
local RLNCEncoder = require("./Encoder")
local RLNCError = require("./Errors")

type RLNCError = RLNCError.RLNCError
type Encoder = RLNCEncoder.Encoder

export type Recoder = {
	GetOriginalNumPiecesCodedTogether: (self: Recoder) -> number,
	GetNumPiecesRecodedTogether: (self: Recoder) -> number,
	GetPieceByteLen: (self: Recoder) -> number,
	GetFullCodedPieceByteLen: (self: Recoder) -> number,
	RecodeWithBuffer: (self: Recoder, FullRecodedPiece: buffer, Random: Random) -> RLNCError?,
	Recode: (self: Recoder, Random: Random) -> buffer,
}

type RecoderInternal = {
	CodingVectors: buffer,
	Encoder: Encoder,
	NumPiecesReceived: number,
	FullCodedPieceByteLen: number,
	NumPiecesCodedTogether: number,
	RandomRecodingVector: buffer,
}

local function GetOriginalNumPiecesCodedTogether(self: RecoderInternal): number
	return self.NumPiecesCodedTogether
end

local function GetNumPiecesRecodedTogether(self: RecoderInternal): number
	return self.NumPiecesReceived
end

local function GetPieceByteLen(self: RecoderInternal): number
	return self.FullCodedPieceByteLen - self.NumPiecesCodedTogether
end

local function GetFullCodedPieceByteLen(self: RecoderInternal): number
	return self.FullCodedPieceByteLen
end

local function RecodeWithBuffer(self: RecoderInternal, FullRecodedPiece: buffer, Random: Random): RLNCError?
	if buffer.len(FullRecodedPiece) ~= self.FullCodedPieceByteLen then
		return RLNCError.InvalidOutputBuffer
	end

	local NumPiecesCodedTogether = self.NumPiecesCodedTogether
	local NumPiecesReceived = self.NumPiecesReceived
	local RandomRecodingVector = self.RandomRecodingVector
	local CodingVectors = self.CodingVectors

	for Index = 0, NumPiecesReceived - 1 do
		buffer.writeu8(RandomRecodingVector, Index, Random:NextInteger(0, 255))
	end

	for CoeffIdx = 0, NumPiecesCodedTogether - 1 do
		local ComputedCoeff = 0

		for RecodingVecIdx = 0, NumPiecesReceived - 1 do
			local RecodingCoeff = buffer.readu8(RandomRecodingVector, RecodingVecIdx)
			local RowBeginsAt = RecodingVecIdx * NumPiecesCodedTogether
			local OriginalCoeff = buffer.readu8(CodingVectors, RowBeginsAt + CoeffIdx)

			local Product = GF256.Mul(RecodingCoeff, OriginalCoeff)
			ComputedCoeff = GF256.Add(ComputedCoeff, Product)
		end

		buffer.writeu8(FullRecodedPiece, CoeffIdx, ComputedCoeff)
	end

	local PieceByteLen = self.FullCodedPieceByteLen - NumPiecesCodedTogether
	local RecodedData = buffer.create(PieceByteLen)

	local Error: RLNCError? = self.Encoder:CodeWithCodingVector(RandomRecodingVector, RecodedData)
	if Error then
		return Error
	end

	buffer.copy(FullRecodedPiece, NumPiecesCodedTogether, RecodedData, 0, PieceByteLen)

	return nil
end

local function Recode(self: RecoderInternal, Random: Random): buffer
	local FullRecodedPiece = buffer.create(self.FullCodedPieceByteLen)
	RecodeWithBuffer(self, FullRecodedPiece, Random)
	return FullRecodedPiece
end

local RecoderMethods = {
	GetOriginalNumPiecesCodedTogether = GetOriginalNumPiecesCodedTogether,
	GetNumPiecesRecodedTogether = GetNumPiecesRecodedTogether,
	GetPieceByteLen = GetPieceByteLen,
	GetFullCodedPieceByteLen = GetFullCodedPieceByteLen,
	RecodeWithBuffer = RecodeWithBuffer,
	Recode = Recode,
}

local function New(Data: buffer, FullCodedPieceByteLen: number, NumPiecesCodedTogether: number): (Recoder?, RLNCError?)
	local DataLen = buffer.len(Data)

	if DataLen == 0 then
		return nil, RLNCError.NotEnoughPiecesToRecode
	end

	if FullCodedPieceByteLen == 0 then
		return nil, RLNCError.PieceLengthZero
	end

	if NumPiecesCodedTogether == 0 then
		return nil, RLNCError.PieceCountZero
	end

	if FullCodedPieceByteLen <= NumPiecesCodedTogether then
		return nil, RLNCError.PieceLengthTooShort
	end

	local PieceByteLen = FullCodedPieceByteLen - NumPiecesCodedTogether
	local NumPiecesReceived = DataLen // FullCodedPieceByteLen

	if NumPiecesReceived == 0 then
		return nil, RLNCError.NotEnoughPiecesToRecode
	end

	local CodingVectorsLen = NumPiecesReceived * NumPiecesCodedTogether
	local CodedPiecesLen = NumPiecesReceived * PieceByteLen

	local CodingVectors = buffer.create(CodingVectorsLen)
	local CodedPieces = buffer.create(CodedPiecesLen)

	for ChunkIndex = 0, NumPiecesReceived - 1 do
		local ChunkStart = ChunkIndex * FullCodedPieceByteLen
		local CodingVectorDest = ChunkIndex * NumPiecesCodedTogether
		local CodedPieceDest = ChunkIndex * PieceByteLen

		buffer.copy(CodingVectors, CodingVectorDest, Data, ChunkStart, NumPiecesCodedTogether)
		buffer.copy(CodedPieces, CodedPieceDest, Data, ChunkStart + NumPiecesCodedTogether, PieceByteLen)
	end

	local Encoder: Encoder?, EncoderError: RLNCError? = RLNCEncoder.WithoutPadding(CodedPieces, NumPiecesReceived)
	if EncoderError then
		return nil, EncoderError
	end

	local self: RecoderInternal = {
		CodingVectors = CodingVectors,
		Encoder = Encoder :: Encoder,
		NumPiecesReceived = NumPiecesReceived,
		FullCodedPieceByteLen = FullCodedPieceByteLen,
		NumPiecesCodedTogether = NumPiecesCodedTogether,
		RandomRecodingVector = buffer.create(NumPiecesReceived),
	}

	return setmetatable(self, { __index = RecoderMethods }) :: any, nil
end

return {
	New = New,
}