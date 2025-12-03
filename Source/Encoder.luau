--[=[
	RLNCEncoder: Random Linear Network Coding Encoder
	
	Responsible for padding data, dividing padded data into pieces, and
	generating coded pieces based on randomly sampled coding vectors.
	
	Structure:
		Encoder holds padded data split into PieceCount pieces of PieceByteLen bytes each.
		Full coded pieces consist of PieceCount random coefficients followed by
		PieceByteLen bytes of coded data.
	
	Return type: Encoder constructor and methods
	
	Example usage:
		local RLNCEncoder = require(path.to.RLNCEncoder)
		
		local Data = buffer.fromstring("Hello, World!")
		local Encoder, Error = RLNCEncoder.New(Data, 4)
		
		if Encoder then
			local CodedPiece = Encoder:Code()
		end
--]=]

--!strict
--!optimize 2
--!native

local GF256 = require("./GF256")
local RLNCError = require("./Errors")
local RLNCConstants = require("./Constants")

type RLNCError = RLNCError.RLNCError

export type Encoder = {
	GetPieceCount: (self: Encoder) -> number,
	GetPieceByteLen: (self: Encoder) -> number,
	GetFullCodedPieceByteLen: (self: Encoder) -> number,
	CodeWithCodingVector: (self: Encoder, CodingVector: buffer, CodedData: buffer) -> RLNCError?,
	CodeWithBuffer: (self: Encoder, FullCodedPiece: buffer, Random: Random) -> RLNCError?,
	Code: (self: Encoder, Random: Random) -> buffer,
}

type EncoderInternal = {
	Data: buffer,
	PieceCount: number,
	PieceByteLen: number,
}

local function GetPieceCount(self: EncoderInternal): number
	return self.PieceCount
end

local function GetPieceByteLen(self: EncoderInternal): number
	return self.PieceByteLen
end

local function GetFullCodedPieceByteLen(self: EncoderInternal): number
	return self.PieceCount + self.PieceByteLen
end

local function CodeWithCodingVector(self: EncoderInternal, CodingVector: buffer, CodedData: buffer): RLNCError?
	local PieceCount = self.PieceCount
	local PieceByteLen = self.PieceByteLen

	if buffer.len(CodingVector) ~= PieceCount then
		return RLNCError.CodingVectorLengthMismatch
	end

	if buffer.len(CodedData) ~= PieceByteLen then
		return RLNCError.InvalidOutputBuffer
	end

	buffer.fill(CodedData, 0, 0)

	local Data = self.Data

	for PieceIndex = 0, PieceCount - 1 do
		local Coefficient = buffer.readu8(CodingVector, PieceIndex)
		local PieceOffset = PieceIndex * PieceByteLen

		for ByteIndex = 0, PieceByteLen - 1 do
			local DataByte = buffer.readu8(Data, PieceOffset + ByteIndex)
			local CodedByte = buffer.readu8(CodedData, ByteIndex)
			local Product = GF256.Mul(DataByte, Coefficient)
			buffer.writeu8(CodedData, ByteIndex, GF256.Add(CodedByte, Product))
		end
	end

	return nil
end

local function CodeWithBuffer(self: EncoderInternal, FullCodedPiece: buffer, Random: Random): RLNCError?
	local PieceCount = self.PieceCount
	local PieceByteLen = self.PieceByteLen
	local ExpectedLen = PieceCount + PieceByteLen

	if buffer.len(FullCodedPiece) ~= ExpectedLen then
		return RLNCError.InvalidOutputBuffer
	end

	for Index = 0, PieceCount - 1 do
		buffer.writeu8(FullCodedPiece, Index, Random:NextInteger(0, 255))
	end

	local CodingVector = buffer.create(PieceCount)
	buffer.copy(CodingVector, 0, FullCodedPiece, 0, PieceCount)

	local CodedData = buffer.create(PieceByteLen)
	local Error = CodeWithCodingVector(self, CodingVector, CodedData)

	if Error then
		return Error :: RLNCError
	end

	buffer.copy(FullCodedPiece, PieceCount, CodedData, 0, PieceByteLen)

	return nil
end

local function Code(self: EncoderInternal, Random: Random): buffer
	local FullCodedPiece = buffer.create(self.PieceCount + self.PieceByteLen)
	CodeWithBuffer(self, FullCodedPiece, Random)
	return FullCodedPiece
end

local EncoderMethods = {
	GetPieceCount = GetPieceCount,
	GetPieceByteLen = GetPieceByteLen,
	GetFullCodedPieceByteLen = GetFullCodedPieceByteLen,
	CodeWithCodingVector = CodeWithCodingVector,
	CodeWithBuffer = CodeWithBuffer,
	Code = Code,
}

local function WithoutPadding(Data: buffer, PieceCount: number): (Encoder?, RLNCError?)
	local DataLen = buffer.len(Data)

	if DataLen == 0 then
		return nil, RLNCError.DataLengthZero
	end

	if PieceCount == 0 then
		return nil, RLNCError.PieceCountZero
	end

	local PieceByteLen = DataLen // PieceCount
	local ComputedTotalLen = PieceByteLen * PieceCount

	if ComputedTotalLen ~= DataLen then
		return nil, RLNCError.DataLengthMismatch
	end

	local DataCopy = buffer.create(DataLen)
	buffer.copy(DataCopy, 0, Data, 0, DataLen)

	local self: EncoderInternal = {
		Data = DataCopy,
		PieceCount = PieceCount,
		PieceByteLen = PieceByteLen,
	}

	return setmetatable(self, { __index = EncoderMethods }) :: any, nil
end

local function New(Data: buffer, PieceCount: number): (Encoder?, RLNCError?)
	local DataLen = buffer.len(Data)

	if DataLen == 0 then
		return nil, RLNCError.DataLengthZero
	end

	if PieceCount == 0 then
		return nil, RLNCError.PieceCountZero
	end

	local BoundaryMarkerLen = 1
	local PieceByteLen = math.ceil((DataLen + BoundaryMarkerLen) / PieceCount)
	local PaddedDataLen = PieceCount * PieceByteLen

	local PaddedData = buffer.create(PaddedDataLen)
	buffer.copy(PaddedData, 0, Data, 0, DataLen)
	buffer.writeu8(PaddedData, DataLen, RLNCConstants.BOUNDARY_MARKER)

	local self: EncoderInternal = {
		Data = PaddedData,
		PieceCount = PieceCount,
		PieceByteLen = PieceByteLen,
	}

	return setmetatable(self, { __index = EncoderMethods }) :: any, nil
end

return {
	New = New,
	WithoutPadding = WithoutPadding,
}