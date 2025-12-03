--[=[
	RLNCDecoder: Random Linear Network Coding Decoder
	
	Manages received coded pieces and performs Gaussian elimination to recover
	original data. Validates padding and boundary markers during extraction.
	
	Structure:
		Decoder maintains an augmented matrix of [coding_vector | coded_data] rows.
		When enough linearly independent pieces are received, RREF reveals the
		original data pieces.
	
	Return type: Decoder constructor and methods
	
	Example usage:
		local RLNCDecoder = require(path.to.RLNCDecoder)
		
		local Decoder, Error = RLNCDecoder.New(256, 4)
		
		if Decoder then
			while not Decoder:IsAlreadyDecoded() do
				local CodedPiece = ReceiveCodedPiece()
				Decoder:Decode(CodedPiece)
			end
			
			local OriginalData, Error = Decoder:GetDecodedData()
		end
--]=]

--!strict
--!optimize 2
--!native

local RLNCDecoderMatrix = require("./DecoderMatrix")
local RLNCError = require("./Errors")
local RLNCConstants = require("./Constants")

type RLNCError = RLNCError.RLNCError
type DecoderMatrix = RLNCDecoderMatrix.DecoderMatrix

export type Decoder = {
	GetNumPiecesCodedTogether: (self: Decoder) -> number,
	GetPieceByteLen: (self: Decoder) -> number,
	GetFullCodedPieceByteLen: (self: Decoder) -> number,
	GetReceivedPieceCount: (self: Decoder) -> number,
	GetUsefulPieceCount: (self: Decoder) -> number,
	GetRemainingPieceCount: (self: Decoder) -> number,
	Decode: (self: Decoder, FullCodedPiece: buffer) -> RLNCError?,
	IsAlreadyDecoded: (self: Decoder) -> boolean,
	GetDecodedData: (self: Decoder) -> (buffer?, RLNCError?),
}

type DecoderInternal = {
	Matrix: DecoderMatrix,
	PieceByteLen: number,
	RequiredPieceCount: number,
	ReceivedPieceCount: number,
	UsefulPieceCount: number,
}

local function GetNumPiecesCodedTogether(self: DecoderInternal): number
	return self.RequiredPieceCount
end

local function GetPieceByteLen(self: DecoderInternal): number
	return self.PieceByteLen
end

local function GetFullCodedPieceByteLen(self: DecoderInternal): number
	return self.RequiredPieceCount + self.PieceByteLen
end

local function GetReceivedPieceCount(self: DecoderInternal): number
	return self.ReceivedPieceCount
end

local function GetUsefulPieceCount(self: DecoderInternal): number
	return self.UsefulPieceCount
end

local function GetRemainingPieceCount(self: DecoderInternal): number
	return self.RequiredPieceCount - self.UsefulPieceCount
end

local function IsAlreadyDecoded(self: DecoderInternal): boolean
	return self.Matrix:Rank() == self.RequiredPieceCount
end

local function Decode(self: DecoderInternal, FullCodedPiece: buffer): RLNCError?
	if IsAlreadyDecoded(self) then
		return RLNCError.ReceivedAllPieces
	end

	local ExpectedLen = self.RequiredPieceCount + self.PieceByteLen
	if buffer.len(FullCodedPiece) ~= ExpectedLen then
		return RLNCError.InvalidPieceLength
	end

	local RankBefore = self.Matrix:Rank()

	local AddError = self.Matrix:AddRow(FullCodedPiece)
	if AddError then
		return AddError :: RLNCError
	end

	self.Matrix:RREF()
	self.ReceivedPieceCount += 1

	local RankAfter = self.Matrix:Rank()

	if RankBefore == RankAfter then
		return RLNCError.PieceNotUseful
	end

	self.UsefulPieceCount = RankAfter
	return nil
end

local function GetFinalDataLen(PaddedData: buffer): (number?, RLNCError?)
	local DataLen = buffer.len(PaddedData)
	if DataLen == 0 then
		return nil, RLNCError.InvalidDecodedDataFormat
	end

	local LastIndex = DataLen - 1
	local BoundaryMarkerIndex: number? = nil

	for I = LastIndex, 0, -1 do
		if buffer.readu8(PaddedData, I) == RLNCConstants.BOUNDARY_MARKER then
			BoundaryMarkerIndex = I
			break
		end
	end

	if BoundaryMarkerIndex == nil or BoundaryMarkerIndex == 0 then
		return nil, RLNCError.InvalidDecodedDataFormat
	end

	for I = BoundaryMarkerIndex + 1, LastIndex do
		if buffer.readu8(PaddedData, I) ~= 0 then
			return nil, RLNCError.InvalidDecodedDataFormat
		end
	end

	return BoundaryMarkerIndex, nil
end

local function GetDecodedData(self: DecoderInternal): (buffer?, RLNCError?)
	if not IsAlreadyDecoded(self) then
		return nil, RLNCError.NotAllPiecesReceivedYet
	end

	local RequiredLen = self.PieceByteLen * self.RequiredPieceCount
	local OutputBuffer = buffer.create(RequiredLen)

	local FullCodedPieceLen = self.RequiredPieceCount + self.PieceByteLen
	local MatrixData = self.Matrix:ExtractData()

	local CurrentPos = 0

	for ChunkIndex = 0, self.RequiredPieceCount - 1 do
		local ChunkStart = ChunkIndex * FullCodedPieceLen
		local PayloadStart = ChunkStart + self.RequiredPieceCount

		buffer.copy(OutputBuffer, CurrentPos, MatrixData, PayloadStart, self.PieceByteLen)
		CurrentPos += self.PieceByteLen
	end

	local FinalLen, Error = GetFinalDataLen(OutputBuffer)
	if Error then
		return nil, Error :: RLNCError
	end

	local FinalBuffer = buffer.create(FinalLen :: number)
	buffer.copy(FinalBuffer, 0, OutputBuffer, 0, FinalLen :: number)

	return FinalBuffer, nil
end

local DecoderMethods = {
	GetNumPiecesCodedTogether = GetNumPiecesCodedTogether,
	GetPieceByteLen = GetPieceByteLen,
	GetFullCodedPieceByteLen = GetFullCodedPieceByteLen,
	GetReceivedPieceCount = GetReceivedPieceCount,
	GetUsefulPieceCount = GetUsefulPieceCount,
	GetRemainingPieceCount = GetRemainingPieceCount,
	Decode = Decode,
	IsAlreadyDecoded = IsAlreadyDecoded,
	GetDecodedData = GetDecodedData,
}

local function New(PieceByteLen: number, RequiredPieceCount: number): (Decoder?, RLNCError?)
	if PieceByteLen == 0 then
		return nil, RLNCError.PieceLengthZero
	end

	if RequiredPieceCount == 0 then
		return nil, RLNCError.PieceCountZero
	end

	local self: DecoderInternal = {
		Matrix = RLNCDecoderMatrix.New(RequiredPieceCount, PieceByteLen),
		PieceByteLen = PieceByteLen,
		RequiredPieceCount = RequiredPieceCount,
		ReceivedPieceCount = 0,
		UsefulPieceCount = 0,
	}

	return setmetatable(self, { __index = DecoderMethods }) :: any, nil
end

return {
	New = New,
}
