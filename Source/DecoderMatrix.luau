--[=[
	RLNCDecoderMatrix: Augmented Matrix for RLNC Decoding
	
	Gaussian elimination over GF(2^8) to decode RLNC coded pieces.
	The matrix stores rows of [coding_vector | coded_data] and reduces to
	RREF (Reduced Row Echelon Form) to recover original data.
	
	Structure:
		Each row is a full coded piece: NumPiecesCoded coefficients + PieceByteLen data bytes.
		Rows are stored contiguously in a single buffer.
	
	Return type: DecoderMatrix class
	
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
	NumPiecesCoded: number,
	Rows: number,
	Cols: number,
	Elements: buffer,
	Capacity: number,
	AddRow: (self: DecoderMatrix, Row: buffer) -> RLNCError?,
	SwapRows: (self: DecoderMatrix, Row1: number, Row2: number) -> (),
	RREF: (self: DecoderMatrix) -> (),
	Rank: (self: DecoderMatrix) -> number,
	ExtractData: (self: DecoderMatrix) -> buffer,
	Get: (self: DecoderMatrix, Row: number, Col: number) -> number,
	Set: (self: DecoderMatrix, Row: number, Col: number, Value: number) -> (),
}

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

local DecoderMatrix = {}
DecoderMatrix.__index = DecoderMatrix

function DecoderMatrix.New(NumPiecesCoded: number, PieceByteLength: number): DecoderMatrix
	local Cols = NumPiecesCoded + PieceByteLength
	local InitialCapacity = NumPiecesCoded * Cols

	local self = {
		NumPiecesCoded = NumPiecesCoded,
		Rows = 0,
		Cols = Cols,
		Elements = buffer.create(InitialCapacity),
		Capacity = InitialCapacity,
	}

	setmetatable(self, DecoderMatrix)

	return (self :: any) :: DecoderMatrix
end

function DecoderMatrix:Get(Row: number, Col: number): number
	local Cols: number = self.Cols
	local Elements: buffer = self.Elements
	local Index = Row * Cols + Col
	return buffer.readu8(Elements, Index)
end

function DecoderMatrix:Set(Row: number, Col: number, Value: number): ()
	local Cols: number = self.Cols
	local Elements: buffer = self.Elements
	local Index = Row * Cols + Col
	buffer.writeu8(Elements, Index, Value)
end

function DecoderMatrix:AddRow(Row: buffer): RLNCError?
	local Cols: number = self.Cols
	local CurrentRows: number = self.Rows
	local RowLen = buffer.len(Row)

	if RowLen ~= Cols then
		return RLNCError.InvalidPieceLength
	end

	local NewRows = CurrentRows + 1
	local RequiredSize = NewRows * Cols

	if RequiredSize > self.Capacity then
		local NewCapacity = math.max(RequiredSize, self.Capacity * 2)
		local NewElements = buffer.create(NewCapacity)
		buffer.copy(NewElements, 0, self.Elements, 0, CurrentRows * Cols)
		self.Elements = NewElements
		self.Capacity = NewCapacity
	end

	local Offset = CurrentRows * Cols
	buffer.copy(self.Elements, Offset, Row, 0, RowLen)
	self.Rows = NewRows

	return nil
end

function DecoderMatrix:SwapRows(Row1: number, Row2: number): ()
	if Row1 == Row2 then
		return
	end

	local Cols: number = self.Cols
	local Elements: buffer = self.Elements
	local Start1 = Row1 * Cols
	local Start2 = Row2 * Cols

	for Offset = 0, Cols - 1 do
		local Temp = buffer.readu8(Elements, Start1 + Offset)
		buffer.writeu8(Elements, Start1 + Offset, buffer.readu8(Elements, Start2 + Offset))
		buffer.writeu8(Elements, Start2 + Offset, Temp)
	end
end

function DecoderMatrix:CleanForward(): ()
	local Rows: number = self.Rows
	local Cols: number = self.Cols
	local Elements: buffer = self.Elements
	local Boundary = math.min(Rows, Cols)

	for I = 0, Boundary - 1 do
		if self:Get(I, I) == 0 then
			local IsNonZeroCol = false
			local PivotRowIdx = I + 1

			while PivotRowIdx < Rows do
				if self:Get(PivotRowIdx, I) ~= 0 then
					IsNonZeroCol = true
					break
				end
				PivotRowIdx += 1
			end

			if not IsNonZeroCol then
				continue
			end

			self:SwapRows(I, PivotRowIdx)
		end

		for J = I + 1, Rows - 1 do
			local JI = self:Get(J, I)
			if JI == 0 then
				continue
			end

			local II = self:Get(I, I)
			local Quotient = GF256.Div(JI, II) :: number

			local IRowStart = I * Cols + I
			local JRowStart = J * Cols + I
			local Length = Cols - I

			MulVecByScalarThenAddIntoVec(Elements, JRowStart, Elements, IRowStart, Length, Quotient)
		end
	end
end

function DecoderMatrix:CleanBackward(): ()
	local Rows: number = self.Rows
	local Cols: number = self.Cols
	local Elements: buffer = self.Elements
	local Boundary = math.min(Rows, Cols)

	for I = Boundary - 1, 0, -1 do
		local II = self:Get(I, I)
		if II == 0 then
			continue
		end

		for J = 0, I - 1 do
			local JI = self:Get(J, I)
			if JI == 0 then
				continue
			end

			local Quotient = GF256.Div(JI, II) :: number

			local JRowStart = J * Cols + I
			local IRowStart = I * Cols + I
			local Length = Cols - I

			MulVecByScalarThenAddIntoVec(Elements, JRowStart, Elements, IRowStart, Length, Quotient)
		end

		if II == 1 then
			continue
		end

		local Inv = GF256.Inv(II) :: number
		self:Set(I, I, 1)

		local IRowStart = I * Cols + I + 1
		local Length = Cols - I - 1

		InplaceMulVecByScalar(Elements, IRowStart, Length, Inv)
	end
end

function DecoderMatrix:RemoveZeroRows(): ()
	local NumPiecesCoded: number = self.NumPiecesCoded
	local Cols: number = self.Cols
	local I = 0

	while I < self.Rows do
		local IsNonZeroRow = false

		for CIdx = 0, NumPiecesCoded - 1 do
			if self:Get(I, CIdx) ~= 0 then
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

function DecoderMatrix:RREF(): ()
	self:CleanForward()
	self:CleanBackward()
	self:RemoveZeroRows()
end

function DecoderMatrix:Rank(): number
	return self.Rows
end

function DecoderMatrix:ExtractData(): buffer
	local Rows: number = self.Rows
	local Cols: number = self.Cols
	local TotalBytes = Rows * Cols
	local Result = buffer.create(TotalBytes)
	buffer.copy(Result, 0, self.Elements, 0, TotalBytes)
	return Result
end

return DecoderMatrix