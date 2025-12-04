--[=[
	GF256: Galois Field GF(2^8) Arithmetic
	
	Finite field arithmetic over GF(2^8) using the irreducible
	polynomial x^8 + x^4 + x^3 + x + 1 with primitive element x = 3.
	
	Return type: Module table with GF256 operations
	
	Example usage:
		local GF256 = require(path.to.GF256)
		
		local A = 0x53
		local B = 0xCA
		
		local Sum = GF256.Add(A, B)
		local Product = GF256.Mul(A, B)
		local Quotient = GF256.Div(A, B)
		local Inverse = GF256.Inv(A)
--]=]

--!strict
--!optimize 2
--!native

local LOG_TABLE, EXP_TABLE = buffer.create(256), buffer.create(512 + 256) do
	local LogValues = {
		0, 0, 25, 1, 50, 2, 26, 198, 75, 199, 27, 104, 51, 238, 223, 3,
		100, 4, 224, 14, 52, 141, 129, 239, 76, 113, 8, 200, 248, 105, 28, 193,
		125, 194, 29, 181, 249, 185, 39, 106, 77, 228, 166, 114, 154, 201, 9, 120,
		101, 47, 138, 5, 33, 15, 225, 36, 18, 240, 130, 69, 53, 147, 218, 142,
		150, 143, 219, 189, 54, 208, 206, 148, 19, 92, 210, 241, 64, 70, 131, 56,
		102, 221, 253, 48, 191, 6, 139, 98, 179, 37, 226, 152, 34, 136, 145, 16,
		126, 110, 72, 195, 163, 182, 30, 66, 58, 107, 40, 84, 250, 133, 61, 186,
		43, 121, 10, 21, 155, 159, 94, 202, 78, 212, 172, 229, 243, 115, 167, 87,
		175, 88, 168, 80, 244, 234, 214, 116, 79, 174, 233, 213, 231, 230, 173, 232,
		44, 215, 117, 122, 235, 22, 11, 245, 89, 203, 95, 176, 156, 169, 81, 160,
		127, 12, 246, 111, 23, 196, 73, 236, 216, 67, 31, 45, 164, 118, 123, 183,
		204, 187, 62, 90, 251, 96, 177, 134, 59, 82, 161, 108, 170, 85, 41, 157,
		151, 178, 135, 144, 97, 190, 220, 252, 188, 149, 207, 205, 55, 63, 91, 209,
		83, 57, 132, 60, 65, 162, 109, 71, 20, 42, 158, 93, 86, 242, 211, 171,
		68, 17, 146, 217, 35, 32, 46, 137, 180, 124, 184, 38, 119, 153, 227, 165,
		103, 74, 237, 222, 197, 49, 254, 24, 13, 99, 140, 128, 192, 247, 112, 7,
	}

	local ExpValues = {
		1, 3, 5, 15, 17, 51, 85, 255, 26, 46, 114, 150, 161, 248, 19, 53,
		95, 225, 56, 72, 216, 115, 149, 164, 247, 2, 6, 10, 30, 34, 102, 170,
		229, 52, 92, 228, 55, 89, 235, 38, 106, 190, 217, 112, 144, 171, 230, 49,
		83, 245, 4, 12, 20, 60, 68, 204, 79, 209, 104, 184, 211, 110, 178, 205,
		76, 212, 103, 169, 224, 59, 77, 215, 98, 166, 241, 8, 24, 40, 120, 136,
		131, 158, 185, 208, 107, 189, 220, 127, 129, 152, 179, 206, 73, 219, 118, 154,
		181, 196, 87, 249, 16, 48, 80, 240, 11, 29, 39, 105, 187, 214, 97, 163,
		254, 25, 43, 125, 135, 146, 173, 236, 47, 113, 147, 174, 233, 32, 96, 160,
		251, 22, 58, 78, 210, 109, 183, 194, 93, 231, 50, 86, 250, 21, 63, 65,
		195, 94, 226, 61, 71, 201, 64, 192, 91, 237, 44, 116, 156, 191, 218, 117,
		159, 186, 213, 100, 172, 239, 42, 126, 130, 157, 188, 223, 122, 142, 137, 128,
		155, 182, 193, 88, 232, 35, 101, 175, 234, 37, 111, 177, 200, 67, 197, 84,
		252, 31, 33, 99, 165, 244, 7, 9, 27, 45, 119, 153, 176, 203, 70, 202,
		69, 207, 74, 222, 121, 139, 134, 145, 168, 227, 62, 66, 198, 81, 243, 14,
		18, 54, 90, 238, 41, 123, 141, 140, 143, 138, 133, 148, 167, 242, 13, 23,
		57, 75, 221, 124, 132, 151, 162, 253, 28, 36, 108, 180, 199, 82, 246,
	}

	for Index, Value in LogValues do
		buffer.writeu8(LOG_TABLE, Index - 1, Value)
	end

	for Index, Value in ExpValues do
		buffer.writeu8(EXP_TABLE, Index - 1, Value)
	end

	for Index = 0, 254 do
		buffer.writeu8(EXP_TABLE, 255 + Index, buffer.readu8(EXP_TABLE, Index))
	end

	for Index = 0, 255 do
		buffer.writeu8(EXP_TABLE, 510 + Index, buffer.readu8(EXP_TABLE, Index))
	end

	buffer.writeu8(EXP_TABLE, 510, 0)
end

local MUL_TABLES = buffer.create(256 * 256) do
	for Scalar = 0, 255 do
		local TableOffset = Scalar * 256
		if Scalar == 0 then
			for I = 0, 255 do
				buffer.writeu8(MUL_TABLES, TableOffset + I, 0)
			end
		else
			local LogScalar = buffer.readu8(LOG_TABLE, Scalar)
			for I = 0, 255 do
				if I == 0 then
					buffer.writeu8(MUL_TABLES, TableOffset, 0)
				else
					local LogI = buffer.readu8(LOG_TABLE, I)
					buffer.writeu8(MUL_TABLES, TableOffset + I, buffer.readu8(EXP_TABLE, LogScalar + LogI))
				end
			end
		end
	end
end

local function Add(A: number, B: number): number
	return bit32.bxor(A, B)
end

local function Sub(A: number, B: number): number
	return bit32.bxor(A, B)
end

local function Neg(A: number): number
	return A
end

local function Mul(A: number, B: number): number
	return buffer.readu8(MUL_TABLES, A * 256 + B)
end

local function Inv(A: number): number?
	if A == 0 then
		return nil
	end

	local LogA = buffer.readu8(LOG_TABLE, A)
	return buffer.readu8(EXP_TABLE, 255 - LogA)
end

local function Div(A: number, B: number): number?
	if B == 0 then
		return nil
	end

	return buffer.readu8(MUL_TABLES, buffer.readu8(EXP_TABLE, 255 - buffer.readu8(LOG_TABLE, B)) * 256 + A)
end

local function Pow(Base: number, Exponent: number): number
	if Exponent == 0 then
		return 1
	end

	if Base == 0 then
		return 0
	end

	local LogBase = buffer.readu8(LOG_TABLE, Base)
	local ScaledLog = (LogBase * Exponent) % 255

	return buffer.readu8(EXP_TABLE, ScaledLog)
end

local function MulAddRow(Dest: buffer, DestOffset: number, Src: buffer, SrcOffset: number, Length: number, Scalar: number)
	if Scalar == 0 then
		return
	end

	local TableOffset = Scalar * 256
	local Tables = MUL_TABLES

	local I = 0
	local LengthMinus7 = Length - 7

	while I < LengthMinus7 do
		local SrcPos = SrcOffset + I
		local DestPos = DestOffset + I

		buffer.writeu8(Dest, DestPos, bit32.bxor(
			buffer.readu8(Dest, DestPos),
			buffer.readu8(Tables, TableOffset + buffer.readu8(Src, SrcPos))
			))
		buffer.writeu8(Dest, DestPos + 1, bit32.bxor(
			buffer.readu8(Dest, DestPos + 1),
			buffer.readu8(Tables, TableOffset + buffer.readu8(Src, SrcPos + 1))
			))
		buffer.writeu8(Dest, DestPos + 2, bit32.bxor(
			buffer.readu8(Dest, DestPos + 2),
			buffer.readu8(Tables, TableOffset + buffer.readu8(Src, SrcPos + 2))
			))
		buffer.writeu8(Dest, DestPos + 3, bit32.bxor(
			buffer.readu8(Dest, DestPos + 3),
			buffer.readu8(Tables, TableOffset + buffer.readu8(Src, SrcPos + 3))
			))
		buffer.writeu8(Dest, DestPos + 4, bit32.bxor(
			buffer.readu8(Dest, DestPos + 4),
			buffer.readu8(Tables, TableOffset + buffer.readu8(Src, SrcPos + 4))
			))
		buffer.writeu8(Dest, DestPos + 5, bit32.bxor(
			buffer.readu8(Dest, DestPos + 5),
			buffer.readu8(Tables, TableOffset + buffer.readu8(Src, SrcPos + 5))
			))
		buffer.writeu8(Dest, DestPos + 6, bit32.bxor(
			buffer.readu8(Dest, DestPos + 6),
			buffer.readu8(Tables, TableOffset + buffer.readu8(Src, SrcPos + 6))
			))
		buffer.writeu8(Dest, DestPos + 7, bit32.bxor(
			buffer.readu8(Dest, DestPos + 7),
			buffer.readu8(Tables, TableOffset + buffer.readu8(Src, SrcPos + 7))
			))

		I += 8
	end

	while I < Length do
		local SrcPos = SrcOffset + I
		local DestPos = DestOffset + I
		buffer.writeu8(Dest, DestPos, bit32.bxor(
			buffer.readu8(Dest, DestPos),
			buffer.readu8(Tables, TableOffset + buffer.readu8(Src, SrcPos))
			))
		I += 1
	end
end

local function MulRow(Buf: buffer, Offset: number, Length: number, Scalar: number)
	if Scalar == 1 then
		return
	end

	local TableOffset = Scalar * 256
	local Tables = MUL_TABLES

	local I = 0
	local LengthMinus7 = Length - 7

	while I < LengthMinus7 do
		local Pos = Offset + I

		buffer.writeu8(Buf, Pos, buffer.readu8(Tables, TableOffset + buffer.readu8(Buf, Pos)))
		buffer.writeu8(Buf, Pos + 1, buffer.readu8(Tables, TableOffset + buffer.readu8(Buf, Pos + 1)))
		buffer.writeu8(Buf, Pos + 2, buffer.readu8(Tables, TableOffset + buffer.readu8(Buf, Pos + 2)))
		buffer.writeu8(Buf, Pos + 3, buffer.readu8(Tables, TableOffset + buffer.readu8(Buf, Pos + 3)))
		buffer.writeu8(Buf, Pos + 4, buffer.readu8(Tables, TableOffset + buffer.readu8(Buf, Pos + 4)))
		buffer.writeu8(Buf, Pos + 5, buffer.readu8(Tables, TableOffset + buffer.readu8(Buf, Pos + 5)))
		buffer.writeu8(Buf, Pos + 6, buffer.readu8(Tables, TableOffset + buffer.readu8(Buf, Pos + 6)))
		buffer.writeu8(Buf, Pos + 7, buffer.readu8(Tables, TableOffset + buffer.readu8(Buf, Pos + 7)))

		I += 8
	end

	while I < Length do
		local Pos = Offset + I
		buffer.writeu8(Buf, Pos, buffer.readu8(Tables, TableOffset + buffer.readu8(Buf, Pos)))
		I += 1
	end
end

return {
	Add = Add,
	Sub = Sub,
	Neg = Neg,
	Mul = Mul,
	Div = Div,
	Inv = Inv,
	Pow = Pow,

	MulAddRow = MulAddRow,
	MulRow = MulRow,

	Zero = 0,
	One = 1,
	PrimitiveElement = 3,
}