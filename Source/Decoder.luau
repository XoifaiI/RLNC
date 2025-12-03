--[=[
	RLNCDecoder: Random Linear Network Coding Decoder
	
	Manages received coded pieces and performs Gaussian elimination to recover
	original data. Validates padding and boundary markers during extraction.
	
	Structure:
		Decoder maintains an augmented matrix of [coding_vector | coded_data] rows.
		When enough linearly independent pieces are received, RREF reveals the
		original data pieces.
	
	Return type: Decoder class
	
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
	Matrix: DecoderMatrix,
	PieceByteLen: number,
	RequiredPieceCount: number,
	ReceivedPieceCount: number,
	UsefulPieceCount: number,
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

local Decoder = {}
Decoder.__index = Decoder

function Decoder.New(PieceByteLen: number, RequiredPieceCount: number): (Decoder?, RLNCError?)
	if PieceByteLen == 0 then
		return nil, RLNCError.PieceLengthZero
	end

	if RequiredPieceCount == 0 then
		return nil, RLNCError.PieceCountZero
	end

	local self = {
		Matrix = RLNCDecoderMatrix.New(RequiredPieceCount, PieceByteLen),
		PieceByteLen = PieceByteLen,
		RequiredPieceCount = RequiredPieceCount,
		ReceivedPieceCount = 0,
		UsefulPieceCount = 0,
	}

	setmetatable(self, Decoder)

	return (self :: any) :: Decoder, nil
end

function Decoder:GetNumPiecesCodedTogether(): number
	return self.RequiredPieceCount
end

function Decoder:GetPieceByteLen(): number
	return self.PieceByteLen
end

function Decoder:GetFullCodedPieceByteLen(): number
	local RequiredPieceCount: number = self.RequiredPieceCount
	local PieceByteLen: number = self.PieceByteLen
	
	return RequiredPieceCount + PieceByteLen
end

function Decoder:GetReceivedPieceCount(): number
	return self.ReceivedPieceCount
end

function Decoder:GetUsefulPieceCount(): number
	return self.UsefulPieceCount
end

function Decoder:GetRemainingPieceCount(): number
	local RequiredPieceCount: number = self.RequiredPieceCount
	local UsefulPieceCount: number = self.UsefulPieceCount
	
	return RequiredPieceCount - UsefulPieceCount
end

function Decoder:IsAlreadyDecoded(): boolean
	local Matrix: DecoderMatrix = self.Matrix
	local RequiredPieceCount: number = self.RequiredPieceCount
	return Matrix:Rank() == RequiredPieceCount
end

function Decoder:Decode(FullCodedPiece: buffer): RLNCError?
	if self:IsAlreadyDecoded() then
		return RLNCError.ReceivedAllPieces
	end

	local RequiredPieceCount: number = self.RequiredPieceCount
	local PieceByteLen: number = self.PieceByteLen
	local Matrix: DecoderMatrix = self.Matrix

	local ExpectedLen = RequiredPieceCount + PieceByteLen
	if buffer.len(FullCodedPiece) ~= ExpectedLen then
		return RLNCError.InvalidPieceLength
	end

	local RankBefore = Matrix:Rank()

	local AddError = Matrix:AddRow(FullCodedPiece)
	if AddError then
		return AddError :: RLNCError
	end

	Matrix:RREF()
	
	local ReceivedPieceCount: number = self.ReceivedPieceCount
	self.ReceivedPieceCount = ReceivedPieceCount + 1

	local RankAfter = Matrix:Rank()

	if RankBefore == RankAfter then
		return RLNCError.PieceNotUseful
	end

	self.UsefulPieceCount = RankAfter
	return nil
end

function Decoder:GetDecodedData(): (buffer?, RLNCError?)
	if not self:IsAlreadyDecoded() then
		return nil, RLNCError.NotAllPiecesReceivedYet
	end

	local RequiredPieceCount: number = self.RequiredPieceCount
	local PieceByteLen: number = self.PieceByteLen
	local Matrix: DecoderMatrix = self.Matrix

	local RequiredLen = PieceByteLen * RequiredPieceCount
	local OutputBuffer = buffer.create(RequiredLen)

	local FullCodedPieceLen = RequiredPieceCount + PieceByteLen
	local MatrixData = Matrix:ExtractData()

	local CurrentPos = 0

	for ChunkIndex = 0, RequiredPieceCount - 1 do
		local ChunkStart = ChunkIndex * FullCodedPieceLen
		local PayloadStart = ChunkStart + RequiredPieceCount

		buffer.copy(OutputBuffer, CurrentPos, MatrixData, PayloadStart, PieceByteLen)
		CurrentPos += PieceByteLen
	end

	local FinalLen, Error = GetFinalDataLen(OutputBuffer)
	if Error then
		return nil, Error :: RLNCError
	end

	local FinalBuffer = buffer.create(FinalLen :: number)
	buffer.copy(FinalBuffer, 0, OutputBuffer, 0, FinalLen :: number)

	return FinalBuffer, nil
end

return Decoder