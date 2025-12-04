--[=[
	RLNCDecoderMatrix: Augmented Matrix for RLNC Decoding 
	
	Gaussian elimination over GF(2^8) to decode RLNC coded pieces.
	The matrix stores rows of [coding_vector | coded_data] and reduces to
	RREF (Reduced Row Echelon Form) to recover original data.
	
	Return type: DecoderMatrix class
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

local GF256Div = GF256.Div
local GF256Inv = GF256.Inv
local GF256MulAddRow = GF256.MulAddRow
local GF256MulRow = GF256.MulRow

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
	local Elements = self.Elements

	if RequiredSize > self.Capacity then
		local NewCapacity = math.max(RequiredSize, self.Capacity * 2)
		local NewElements = buffer.create(NewCapacity)
		buffer.copy(NewElements, 0, Elements, 0, CurrentRows * Cols)
		Elements = NewElements
		self.Elements = NewElements
		self.Capacity = NewCapacity
	end

	local Offset = CurrentRows * Cols
	buffer.copy(Elements, Offset, Row, 0, RowLen)
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
		local Pos1 = Start1 + Offset
		local Pos2 = Start2 + Offset
		local Temp = buffer.readu8(Elements, Pos1)
		buffer.writeu8(Elements, Pos1, buffer.readu8(Elements, Pos2))
		buffer.writeu8(Elements, Pos2, Temp)
	end
end

function DecoderMatrix:CleanForward(): ()
	local Rows: number = self.Rows
	local Cols: number = self.Cols
	local Elements: buffer = self.Elements
	local Boundary = math.min(Rows, Cols)
	local Div = GF256Div
	local MulAddRow = GF256MulAddRow

	for I = 0, Boundary - 1 do
		local DiagIndex = I * Cols + I
		local DiagValue = buffer.readu8(Elements, DiagIndex)

		if DiagValue == 0 then
			local PivotRowIdx = I + 1

			while PivotRowIdx < Rows do
				local PivotIndex = PivotRowIdx * Cols + I
				if buffer.readu8(Elements, PivotIndex) ~= 0 then
					break
				end
				PivotRowIdx += 1
			end

			if PivotRowIdx >= Rows then
				continue
			end

			self:SwapRows(I, PivotRowIdx)
			DiagValue = buffer.readu8(Elements, DiagIndex)
		end

		local IRowStart = I * Cols + I
		local Length = Cols - I

		for J = I + 1, Rows - 1 do
			local JIIndex = J * Cols + I
			local JI = buffer.readu8(Elements, JIIndex)
			if JI == 0 then
				continue
			end

			local Quotient = Div(JI, DiagValue) :: number
			local JRowStart = J * Cols + I

			MulAddRow(Elements, JRowStart, Elements, IRowStart, Length, Quotient)
		end
	end
end

function DecoderMatrix:CleanBackward(): ()
	local Rows: number = self.Rows
	local Cols: number = self.Cols
	local Elements: buffer = self.Elements
	local Boundary = math.min(Rows, Cols)
	local Div = GF256Div
	local Inv = GF256Inv
	local MulAddRow = GF256MulAddRow
	local MulRow = GF256MulRow

	for I = Boundary - 1, 0, -1 do
		local DiagIndex = I * Cols + I
		local II = buffer.readu8(Elements, DiagIndex)
		if II == 0 then
			continue
		end

		local IRowStart = I * Cols + I
		local Length = Cols - I

		for J = 0, I - 1 do
			local JIIndex = J * Cols + I
			local JI = buffer.readu8(Elements, JIIndex)
			if JI == 0 then
				continue
			end

			local Quotient = Div(JI, II) :: number
			local JRowStart = J * Cols + I

			MulAddRow(Elements, JRowStart, Elements, IRowStart, Length, Quotient)
		end

		if II == 1 then
			continue
		end

		local InvII = Inv(II) :: number
		buffer.writeu8(Elements, DiagIndex, 1)

		MulRow(Elements, IRowStart + 1, Length - 1, InvII)
	end
end

function DecoderMatrix:RemoveZeroRows(): ()
	local NumPiecesCoded: number = self.NumPiecesCoded
	local Cols: number = self.Cols
	local Elements: buffer = self.Elements
	local I = 0

	while I < self.Rows do
		local IsNonZeroRow = false
		local RowStart = I * Cols

		for CIdx = 0, NumPiecesCoded - 1 do
			if buffer.readu8(Elements, RowStart + CIdx) ~= 0 then
				IsNonZeroRow = true
				break
			end
		end

		if IsNonZeroRow then
			I += 1
			continue
		end

		local CurrentRows = self.Rows
		local StartIdxToRemove = I * Cols
		local StartIdxNextRow = (I + 1) * Cols
		local TotalElements = CurrentRows * Cols

		if StartIdxNextRow < TotalElements then
			buffer.copy(Elements, StartIdxToRemove, Elements, StartIdxNextRow, TotalElements - StartIdxNextRow)
		end

		self.Rows = CurrentRows - 1
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