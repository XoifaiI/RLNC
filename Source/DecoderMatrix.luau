--[=[
	RLNCDecoderMatrix: Augmented Matrix for RLNC Decoding
	
	Gaussian elimination over GF(2^8) to decode RLNC coded pieces.
	The matrix stores rows of [coding_vector | coded_data] and reduces to
	RREF (Reduced Row Echelon Form) to recover original data.
	
	Structure:
		Each row is a full coded piece: NumPiecesCoded coefficients + PieceByteLen data bytes.
		Rows are stored contiguously in a single buffer.
	
	Return type: DecoderMatrix constructor and methods
	
	Example usage:
		local RLNCDecoderMatrix = require(path.to.RLNCDecoderMatrix)
		
		local Matrix = RLNCDecoderMatrix.New(4, 256)
		Matrix:AddRow(CodedPiece1)
		Matrix:AddRow(CodedPiece2)
		Matrix:RREF()
		
		if Matrix:Rank() == 4 then
			local DecodedData = Matrix:ExtractData()
		end
--]=]

--!strict
--!optimize 2
--!native

local GF256 = require("./GF256")
local RLNCError = require("./Errors")

type RLNCError = RLNCError.RLNCError

export type DecoderMatrix = {
	AddRow: (self: DecoderMatrix, Row: buffer) -> RLNCError?,
	SwapRows: (self: DecoderMatrix, Row1: number, Row2: number) -> (),
	RREF: (self: DecoderMatrix) -> (),
	Rank: (self: DecoderMatrix) -> number,
	ExtractData: (self: DecoderMatrix) -> buffer,
	Get: (self: DecoderMatrix, Row: number, Col: number) -> number,
	Set: (self: DecoderMatrix, Row: number, Col: number, Value: number) -> (),
}

type DecoderMatrixInternal = {
	NumPiecesCoded: number,
	Rows: number,
	Cols: number,
	Elements: buffer,
	Capacity: number,
}

local function Get(self: DecoderMatrixInternal, Row: number, Col: number): number
	local Index = Row * self.Cols + Col
	return buffer.readu8(self.Elements, Index)
end

local function Set(self: DecoderMatrixInternal, Row: number, Col: number, Value: number)
	local Index = Row * self.Cols + Col
	buffer.writeu8(self.Elements, Index, Value)
end

local function AddRow(self: DecoderMatrixInternal, Row: buffer): RLNCError?
	local RowLen = buffer.len(Row)

	if RowLen ~= self.Cols then
		return RLNCError.InvalidPieceLength
	end

	local NewRows = self.Rows + 1
	local RequiredSize = NewRows * self.Cols

	if RequiredSize > self.Capacity then
		local NewCapacity = math.max(RequiredSize, self.Capacity * 2)
		local NewElements = buffer.create(NewCapacity)
		buffer.copy(NewElements, 0, self.Elements, 0, self.Rows * self.Cols)
		self.Elements = NewElements
		self.Capacity = NewCapacity
	end

	local Offset = self.Rows * self.Cols
	buffer.copy(self.Elements, Offset, Row, 0, RowLen)
	self.Rows = NewRows

	return nil
end

local function SwapRows(self: DecoderMatrixInternal, Row1: number, Row2: number)
	if Row1 == Row2 then
		return
	end

	local Cols = self.Cols
	local Elements = self.Elements
	local Start1 = Row1 * Cols
	local Start2 = Row2 * Cols

	for Offset = 0, Cols - 1 do
		local Temp = buffer.readu8(Elements, Start1 + Offset)
		buffer.writeu8(Elements, Start1 + Offset, buffer.readu8(Elements, Start2 + Offset))
		buffer.writeu8(Elements, Start2 + Offset, Temp)
	end
end

local function MulVecByScalarThenAddIntoVec(
	Dest: buffer,
	DestOffset: number,
	Src: buffer,
	SrcOffset: number,
	Length: number,
	Scalar: number
)
	if Scalar == 0 then
		return
	end

	for Index = 0, Length - 1 do
		local SrcByte = buffer.readu8(Src, SrcOffset + Index)
		local DestByte = buffer.readu8(Dest, DestOffset + Index)
		local Product = GF256.Mul(SrcByte, Scalar)
		buffer.writeu8(Dest, DestOffset + Index, GF256.Add(DestByte, Product))
	end
end

local function InplaceMulVecByScalar(Buf: buffer, Offset: number, Length: number, Scalar: number)
	if Scalar == 1 then
		return
	end

	for Index = 0, Length - 1 do
		local Byte = buffer.readu8(Buf, Offset + Index)
		buffer.writeu8(Buf, Offset + Index, GF256.Mul(Byte, Scalar))
	end
end

local function CleanForward(self: DecoderMatrixInternal)
	local Rows = self.Rows
	local Cols = self.Cols
	local Boundary = math.min(Rows, Cols)

	for I = 0, Boundary - 1 do
		if Get(self, I, I) == 0 then
			local IsNonZeroCol = false
			local PivotRowIdx = I + 1

			while PivotRowIdx < Rows do
				if Get(self, PivotRowIdx, I) ~= 0 then
					IsNonZeroCol = true
					break
				end
				PivotRowIdx += 1
			end

			if not IsNonZeroCol then
				continue
			end

			SwapRows(self, I, PivotRowIdx)
		end

		for J = I + 1, Rows - 1 do
			local JI = Get(self, J, I)
			if JI == 0 then
				continue
			end

			local II = Get(self, I, I)
			local Quotient = GF256.Div(JI, II) :: number

			local IRowStart = I * Cols + I
			local JRowStart = J * Cols + I
			local Length = Cols - I

			MulVecByScalarThenAddIntoVec(self.Elements, JRowStart, self.Elements, IRowStart, Length, Quotient)
		end
	end
end

local function CleanBackward(self: DecoderMatrixInternal)
	local Rows = self.Rows
	local Cols = self.Cols
	local Boundary = math.min(Rows, Cols)

	for I = Boundary - 1, 0, -1 do
		local II = Get(self, I, I)
		if II == 0 then
			continue
		end

		for J = 0, I - 1 do
			local JI = Get(self, J, I)
			if JI == 0 then
				continue
			end

			local Quotient = GF256.Div(JI, II) :: number

			local JRowStart = J * Cols + I
			local IRowStart = I * Cols + I
			local Length = Cols - I

			MulVecByScalarThenAddIntoVec(self.Elements, JRowStart, self.Elements, IRowStart, Length, Quotient)
		end

		if II == 1 then
			continue
		end

		local Inv = GF256.Inv(II) :: number
		Set(self, I, I, 1)

		local IRowStart = I * Cols + I + 1
		local Length = Cols - I - 1

		InplaceMulVecByScalar(self.Elements, IRowStart, Length, Inv)
	end
end

local function RemoveZeroRows(self: DecoderMatrixInternal)
	local NumPiecesCoded = self.NumPiecesCoded
	local Cols = self.Cols
	local I = 0

	while I < self.Rows do
		local IsNonZeroRow = false

		for CIdx = 0, NumPiecesCoded - 1 do
			if Get(self, I, CIdx) ~= 0 then
				IsNonZeroRow = true
				break
			end
		end

		if IsNonZeroRow then
			I += 1
			continue
		end

		local StartIdxToRemove = I * Cols
		local StartIdxNextRow = (I + 1) * Cols
		local TotalElements = self.Rows * Cols

		if StartIdxNextRow < TotalElements then
			buffer.copy(self.Elements, StartIdxToRemove, self.Elements, StartIdxNextRow, TotalElements - StartIdxNextRow)
		end

		self.Rows -= 1
	end
end

local function RREF(self: DecoderMatrixInternal)
	CleanForward(self)
	CleanBackward(self)
	RemoveZeroRows(self)
end

local function Rank(self: DecoderMatrixInternal): number
	return self.Rows
end

local function ExtractData(self: DecoderMatrixInternal): buffer
	local TotalBytes = self.Rows * self.Cols
	local Result = buffer.create(TotalBytes)
	buffer.copy(Result, 0, self.Elements, 0, TotalBytes)
	return Result
end

local DecoderMatrixMethods = {
	AddRow = AddRow,
	SwapRows = SwapRows,
	RREF = RREF,
	Rank = Rank,
	ExtractData = ExtractData,
	Get = Get,
	Set = Set,
}

local function New(NumPiecesCoded: number, PieceByteLength: number): DecoderMatrix
	local Cols = NumPiecesCoded + PieceByteLength
	local InitialCapacity = NumPiecesCoded * Cols

	local self: DecoderMatrixInternal = {
		NumPiecesCoded = NumPiecesCoded,
		Rows = 0,
		Cols = Cols,
		Elements = buffer.create(InitialCapacity),
		Capacity = InitialCapacity,
	}

	return setmetatable(self, { __index = DecoderMatrixMethods }) :: any
end

return {
	New = New,
}
