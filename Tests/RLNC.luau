--!strict
--!optimize 2

local Testing = require("../Testing")
local RLNC = require("../../RLNC")

local Encoder = RLNC.Encoder
local Decoder = RLNC.Decoder
local Recoder = RLNC.Recoder
local DecoderMatrix = RLNC.DecoderMatrix
local GF256 = RLNC.GF256
local RLNCError = RLNC.Error

Testing.Entry(function()
	Testing.Describe("GF256", function()
		Testing.Test("prop_test_gf256_operations", function()
			local NumIterations = 100000
			local RNG = Random.new()

			for _ = 1, NumIterations do
				local A = RNG:NextInteger(0, 255)
				local B = RNG:NextInteger(0, 255)

				local Sum = GF256.Add(A, B)
				local Diff = GF256.Sub(Sum, B)
				Testing.Expect(Diff).ToBe(A)

				local Mul = GF256.Mul(A, B)
				local Div = GF256.Div(Mul, B)

				if B == 0 then
					Testing.Expect(Div).ToBeNil()
					Testing.Expect(Mul).ToBe(0)
				else
					Testing.Expect(Div).ToBe(A)
				end
			end
		end)

		Testing.Test("gf256_identity_properties", function()
			local RNG = Random.new()

			for _ = 1, 1000 do
				local A = RNG:NextInteger(0, 255)

				Testing.Expect(GF256.Add(A, 0)).ToBe(A)
				Testing.Expect(GF256.Mul(A, 1)).ToBe(A)
				Testing.Expect(GF256.Mul(A, 0)).ToBe(0)
				Testing.Expect(GF256.Sub(A, A)).ToBe(0)
				Testing.Expect(GF256.Neg(A)).ToBe(A)
			end
		end)

		Testing.Test("gf256_inverse_properties", function()
			for A = 1, 255 do
				local Inv = GF256.Inv(A) :: number
				Testing.Expect(Inv).Never.ToBeNil()
				Testing.Expect(GF256.Mul(A, Inv)).ToBe(1)
			end

			Testing.Expect(GF256.Inv(0)).ToBeNil()
		end)

		Testing.Test("gf256_power_properties", function()
			local RNG = Random.new()

			for _ = 1, 1000 do
				local Base = RNG:NextInteger(1, 255)

				Testing.Expect(GF256.Pow(Base, 0)).ToBe(1)
				Testing.Expect(GF256.Pow(Base, 1)).ToBe(Base)
				Testing.Expect(GF256.Pow(0, 5)).ToBe(0)

				local Exp = RNG:NextInteger(2, 10)
				local Manual = Base
				for _ = 2, Exp do
					Manual = GF256.Mul(Manual, Base)
				end
				Testing.Expect(GF256.Pow(Base, Exp)).ToBe(Manual)
			end
		end)
	end)

	Testing.Describe("DecoderMatrix", function()
		Testing.Test("prop_test_rref_is_idempotent", function()
			local NumIterations = 100
			local MinRows, MaxRows = 1, 100
			local MinCols, MaxCols = 1, 100
			local RNG = Random.new()

			for _ = 1, NumIterations do
				local NumPieces = RNG:NextInteger(MinRows, MaxRows)
				local PieceLen = RNG:NextInteger(MinCols, MaxCols)

				local Matrix = DecoderMatrix.New(NumPieces, PieceLen)
				local RowLen = NumPieces + PieceLen

				local NumRowsToAdd = RNG:NextInteger(1, NumPieces)
				for _ = 1, NumRowsToAdd do
					local Row = buffer.create(RowLen)
					for I = 0, RowLen - 1 do
						buffer.writeu8(Row, I, RNG:NextInteger(0, 255))
					end
					Matrix:AddRow(Row)
				end

				Matrix:RREF()
				local FirstData = Matrix:ExtractData()
				local FirstRank = Matrix:Rank()

				Matrix:RREF()
				local SecondData = Matrix:ExtractData()
				local SecondRank = Matrix:Rank()

				Testing.Expect(FirstRank).ToBe(SecondRank)
				Testing.Expect(buffer.tostring(FirstData)).ToBe(buffer.tostring(SecondData))
			end
		end)

		Testing.Test("swap_rows", function()
			local NumPieces = 3
			local PieceLen = 2
			local RowLen = NumPieces + PieceLen

			local function MakeRow(...): buffer
				local Values = { ... }
				local Row = buffer.create(RowLen)
				for I, V in Values do
					buffer.writeu8(Row, I - 1, V)
				end
				return Row
			end

			local Matrix = DecoderMatrix.New(NumPieces, PieceLen)
			Matrix:AddRow(MakeRow(1, 1, 1, 10, 10))
			Matrix:AddRow(MakeRow(2, 2, 2, 20, 20))
			Matrix:AddRow(MakeRow(3, 3, 3, 30, 30))
			Matrix:AddRow(MakeRow(4, 4, 4, 40, 40))

			local MatrixCopy = DecoderMatrix.New(NumPieces, PieceLen)
			MatrixCopy:AddRow(MakeRow(1, 1, 1, 10, 10))
			MatrixCopy:AddRow(MakeRow(2, 2, 2, 20, 20))
			MatrixCopy:AddRow(MakeRow(3, 3, 3, 30, 30))
			MatrixCopy:AddRow(MakeRow(4, 4, 4, 40, 40))

			MatrixCopy:SwapRows(0, 2)
			Testing.Expect(MatrixCopy:Get(0, 0)).ToBe(3)
			Testing.Expect(MatrixCopy:Get(0, 3)).ToBe(30)
			Testing.Expect(MatrixCopy:Get(2, 0)).ToBe(1)
			Testing.Expect(MatrixCopy:Get(2, 3)).ToBe(10)

			local IdentityMatrix = DecoderMatrix.New(NumPieces, PieceLen)
			IdentityMatrix:AddRow(MakeRow(1, 1, 1, 10, 10))
			IdentityMatrix:AddRow(MakeRow(2, 2, 2, 20, 20))
			IdentityMatrix:SwapRows(0, 0)
			Testing.Expect(IdentityMatrix:Get(0, 0)).ToBe(1)
			Testing.Expect(IdentityMatrix:Get(1, 0)).ToBe(2)
		end)

		Testing.Test("add_row_validates_length", function()
			local Matrix = DecoderMatrix.New(4, 8)
			local ExpectedLen = 4 + 8

			local ShortRow = buffer.create(ExpectedLen - 1)
			Testing.Expect(Matrix:AddRow(ShortRow)).ToBe(RLNCError.InvalidPieceLength)

			local LongRow = buffer.create(ExpectedLen + 1)
			Testing.Expect(Matrix:AddRow(LongRow)).ToBe(RLNCError.InvalidPieceLength)

			local ValidRow = buffer.create(ExpectedLen)
			Testing.Expect(Matrix:AddRow(ValidRow)).ToBeNil()
			Testing.Expect(Matrix:Rank()).ToBe(1)
		end)
	end)

	Testing.Describe("Encoder", function()
		Testing.Test("new_invalid_inputs", function()
			local RNG = Random.new()

			local EmptyData = buffer.create(0)
			local Enc1, Err1 = Encoder.New(EmptyData, 10)
			Testing.Expect(Enc1).ToBeNil()
			Testing.Expect(Err1).ToBe(RLNCError.DataLengthZero)

			local ValidData = buffer.create(100)
			for I = 0, 99 do
				buffer.writeu8(ValidData, I, RNG:NextInteger(0, 255))
			end
			local Enc2, Err2 = Encoder.New(ValidData, 0)
			Testing.Expect(Enc2).ToBeNil()
			Testing.Expect(Err2).ToBe(RLNCError.PieceCountZero)

			local Enc3, Err3 = Encoder.New(EmptyData, 0)
			Testing.Expect(Enc3).ToBeNil()
			Testing.Expect(Err3).ToBe(RLNCError.DataLengthZero)

			local Enc4 = Encoder.New(ValidData, 10)
			Testing.Expect(Enc4).Never.ToBeNil()
		end)

		Testing.Test("without_padding_invalid_data", function()
			local RNG = Random.new()

			local EmptyData = buffer.create(0)
			local Enc1, Err1 = Encoder.WithoutPadding(EmptyData, 10)
			Testing.Expect(Enc1).ToBeNil()
			Testing.Expect(Err1).ToBe(RLNCError.DataLengthZero)

			local ValidData = buffer.create(100)
			for I = 0, 99 do
				buffer.writeu8(ValidData, I, RNG:NextInteger(0, 255))
			end
			local Enc2, Err2 = Encoder.WithoutPadding(ValidData, 0)
			Testing.Expect(Enc2).ToBeNil()
			Testing.Expect(Err2).ToBe(RLNCError.PieceCountZero)

			local MismatchData = buffer.create(1001)
			local Enc3, Err3 = Encoder.WithoutPadding(MismatchData, 32)
			Testing.Expect(Enc3).ToBeNil()
			Testing.Expect(Err3).ToBe(RLNCError.DataLengthMismatch)

			local Enc4 = Encoder.WithoutPadding(ValidData, 10)
			Testing.Expect(Enc4).Never.ToBeNil()
		end)

		Testing.Test("code_with_coding_vector_invalid_inputs", function()
			local RNG = Random.new()
			local DataLen = 1024
			local PieceCount = 32

			local Data = buffer.create(DataLen)
			for I = 0, DataLen - 1 do
				buffer.writeu8(Data, I, RNG:NextInteger(0, 255))
			end

			local Enc = Encoder.New(Data, PieceCount) :: RLNC.Encoder

			local ShortVector = buffer.create(PieceCount - 1)
			local CodedData = buffer.create(Enc:GetPieceByteLen())
			Testing.Expect(Enc:CodeWithCodingVector(ShortVector, CodedData)).ToBe(RLNCError.CodingVectorLengthMismatch)

			local LongVector = buffer.create(PieceCount + 1)
			Testing.Expect(Enc:CodeWithCodingVector(LongVector, CodedData)).ToBe(RLNCError.CodingVectorLengthMismatch)

			local ValidVector = buffer.create(PieceCount)
			local ShortCodedData = buffer.create(Enc:GetPieceByteLen() - 1)
			Testing.Expect(Enc:CodeWithCodingVector(ValidVector, ShortCodedData)).ToBe(RLNCError.InvalidOutputBuffer)

			local ValidCodedData = buffer.create(Enc:GetPieceByteLen())
			Testing.Expect(Enc:CodeWithCodingVector(ValidVector, ValidCodedData)).ToBeNil()
		end)

		Testing.Test("code_with_buffer_invalid_inputs", function()
			local RNG = Random.new()
			local DataLen = 1024
			local PieceCount = 32

			local Data = buffer.create(DataLen)
			for I = 0, DataLen - 1 do
				buffer.writeu8(Data, I, RNG:NextInteger(0, 255))
			end

			local Enc = Encoder.New(Data, PieceCount) :: RLNC.Encoder

			local ShortBuffer = buffer.create(Enc:GetFullCodedPieceByteLen() - 1)
			Testing.Expect(Enc:CodeWithBuffer(ShortBuffer, RNG)).ToBe(RLNCError.InvalidOutputBuffer)

			local LongBuffer = buffer.create(Enc:GetFullCodedPieceByteLen() + 1)
			Testing.Expect(Enc:CodeWithBuffer(LongBuffer, RNG)).ToBe(RLNCError.InvalidOutputBuffer)

			local EmptyBuffer = buffer.create(0)
			Testing.Expect(Enc:CodeWithBuffer(EmptyBuffer, RNG)).ToBe(RLNCError.InvalidOutputBuffer)

			local ValidBuffer = buffer.create(Enc:GetFullCodedPieceByteLen())
			Testing.Expect(Enc:CodeWithBuffer(ValidBuffer, RNG)).ToBeNil()
		end)

		Testing.Test("getters", function()
			local RNG = Random.new()

			local DataSingle = buffer.create(100)
			for I = 0, 99 do
				buffer.writeu8(DataSingle, I, RNG:NextInteger(0, 255))
			end
			local EncSingle = Encoder.New(DataSingle, 1) :: RLNC.Encoder
			Testing.Expect(EncSingle:GetPieceCount()).ToBe(1)
			Testing.Expect(EncSingle:GetPieceByteLen()).ToBe(101)
			Testing.Expect(EncSingle:GetFullCodedPieceByteLen()).ToBe(102)

			local DataMin = buffer.fromstring(string.char(42))
			local EncMin = Encoder.New(DataMin, 1) :: RLNC.Encoder
			Testing.Expect(EncMin:GetPieceCount()).ToBe(1)
			Testing.Expect(EncMin:GetPieceByteLen()).ToBe(2)
			Testing.Expect(EncMin:GetFullCodedPieceByteLen()).ToBe(3)

			local DataEq = buffer.create(10)
			local EncEq = Encoder.New(DataEq, 10) :: RLNC.Encoder
			Testing.Expect(EncEq:GetPieceCount()).ToBe(10)
			Testing.Expect(EncEq:GetPieceByteLen()).ToBe(2)
			Testing.Expect(EncEq:GetFullCodedPieceByteLen()).ToBe(12)
		end)
	end)

	Testing.Describe("Decoder", function()
		Testing.Test("new_invalid_inputs", function()
			local Dec1, Err1 = Decoder.New(0, 10)
			Testing.Expect(Dec1).ToBeNil()
			Testing.Expect(Err1).ToBe(RLNCError.PieceLengthZero)

			local Dec2, Err2 = Decoder.New(10, 0)
			Testing.Expect(Dec2).ToBeNil()
			Testing.Expect(Err2).ToBe(RLNCError.PieceCountZero)

			local Dec3, Err3 = Decoder.New(0, 0)
			Testing.Expect(Dec3).ToBeNil()
			Testing.Expect(Err3).ToBe(RLNCError.PieceLengthZero)

			local Dec4 = Decoder.New(10, 5)
			Testing.Expect(Dec4).Never.ToBeNil()
		end)

		Testing.Test("decode_invalid_piece_length", function()
			local RNG = Random.new()
			local DataLen = 1024
			local PieceCount = 32

			local Data = buffer.create(DataLen)
			for I = 0, DataLen - 1 do
				buffer.writeu8(Data, I, RNG:NextInteger(0, 255))
			end

			local Enc = Encoder.New(Data, PieceCount) :: RLNC.Encoder
			local Dec = Decoder.New(Enc:GetPieceByteLen(), Enc:GetPieceCount()) :: RLNC.Decoder

			local ShortPiece = buffer.create(Enc:GetFullCodedPieceByteLen() - 1)
			Testing.Expect(Dec:Decode(ShortPiece)).ToBe(RLNCError.InvalidPieceLength)

			local LongPiece = buffer.create(Enc:GetFullCodedPieceByteLen() + 1)
			Testing.Expect(Dec:Decode(LongPiece)).ToBe(RLNCError.InvalidPieceLength)

			local EmptyPiece = buffer.create(0)
			Testing.Expect(Dec:Decode(EmptyPiece)).ToBe(RLNCError.InvalidPieceLength)

			Testing.Expect(Dec:GetReceivedPieceCount()).ToBe(0)
			Testing.Expect(Dec:GetUsefulPieceCount()).ToBe(0)
			Testing.Expect(Dec:IsAlreadyDecoded()).ToBe(false)

			local ValidPiece = Enc:Code(RNG)
			local Result = Dec:Decode(ValidPiece)
			Testing.Expect(Dec:GetReceivedPieceCount()).ToBe(1)
		end)

		Testing.Test("getters", function()
			local RNG = Random.new()
			local DataLen = 1024
			local PieceCount = 32

			local Data = buffer.create(DataLen)
			for I = 0, DataLen - 1 do
				buffer.writeu8(Data, I, RNG:NextInteger(0, 255))
			end

			local Enc = Encoder.New(Data, PieceCount) :: RLNC.Encoder
			local Dec = Decoder.New(Enc:GetPieceByteLen(), Enc:GetPieceCount()) :: RLNC.Decoder

			Testing.Expect(Dec:GetNumPiecesCodedTogether()).ToBe(PieceCount)
			Testing.Expect(Dec:GetPieceByteLen()).ToBe(Enc:GetPieceByteLen())
			Testing.Expect(Dec:GetFullCodedPieceByteLen()).ToBe(Enc:GetFullCodedPieceByteLen())
			Testing.Expect(Dec:GetReceivedPieceCount()).ToBe(0)
			Testing.Expect(Dec:GetUsefulPieceCount()).ToBe(0)
			Testing.Expect(Dec:GetRemainingPieceCount()).ToBe(PieceCount)
			Testing.Expect(Dec:IsAlreadyDecoded()).ToBe(false)

			local HalfPieces = PieceCount // 2
			local UsefulCount = 0
			for _ = 1, HalfPieces do
				local Piece = Enc:Code(RNG)
				local Result = Dec:Decode(Piece)
				if Result == nil then
					UsefulCount += 1
				end
			end

			Testing.Expect(Dec:GetReceivedPieceCount()).ToBe(HalfPieces)
			Testing.Expect(Dec:GetUsefulPieceCount()).ToBe(UsefulCount)
			Testing.Expect(Dec:GetRemainingPieceCount()).ToBe(PieceCount - UsefulCount)

			while not Dec:IsAlreadyDecoded() do
				local Piece = Enc:Code(RNG)
				local Result = Dec:Decode(Piece)
				if Result == RLNCError.ReceivedAllPieces then
					break
				end
			end

			Testing.Expect(Dec:GetUsefulPieceCount()).ToBe(PieceCount)
			Testing.Expect(Dec:GetRemainingPieceCount()).ToBe(0)
			Testing.Expect(Dec:IsAlreadyDecoded()).ToBe(true)
		end)
	end)

	Testing.Describe("Recoder", function()
		Testing.Test("new_invalid_inputs", function()
			local RNG = Random.new()
			local DataLen = 1024
			local PieceCount = 32

			local Data = buffer.create(DataLen)
			for I = 0, DataLen - 1 do
				buffer.writeu8(Data, I, RNG:NextInteger(0, 255))
			end

			local Enc = Encoder.New(Data, PieceCount) :: RLNC.Encoder
			local FullLen = Enc:GetFullCodedPieceByteLen()

			local EmptyData = buffer.create(0)
			local Rec1, Err1 = Recoder.New(EmptyData, FullLen, PieceCount)
			Testing.Expect(Rec1).ToBeNil()
			Testing.Expect(Err1).ToBe(RLNCError.NotEnoughPiecesToRecode)

			local SomeData = buffer.create(3)
			local Rec2, Err2 = Recoder.New(SomeData, 0, PieceCount)
			Testing.Expect(Rec2).ToBeNil()
			Testing.Expect(Err2).ToBe(RLNCError.PieceLengthZero)

			local Rec3, Err3 = Recoder.New(SomeData, FullLen, 0)
			Testing.Expect(Rec3).ToBeNil()
			Testing.Expect(Err3).ToBe(RLNCError.PieceCountZero)

			local Rec4, Err4 = Recoder.New(SomeData, PieceCount, PieceCount)
			Testing.Expect(Rec4).ToBeNil()
			Testing.Expect(Err4).ToBe(RLNCError.PieceLengthTooShort)

			local Rec5, Err5 = Recoder.New(SomeData, PieceCount - 1, PieceCount)
			Testing.Expect(Rec5).ToBeNil()
			Testing.Expect(Err5).ToBe(RLNCError.PieceLengthTooShort)

			local NumPieces = 5
			local CodedPieces = buffer.create(NumPieces * FullLen)
			for I = 0, NumPieces - 1 do
				local Piece = Enc:Code(RNG)
				buffer.copy(CodedPieces, I * FullLen, Piece, 0, FullLen)
			end

			local Rec6 = Recoder.New(CodedPieces, FullLen, PieceCount)
			Testing.Expect(Rec6).Never.ToBeNil()
		end)

		Testing.Test("recode_with_buf_invalid_inputs", function()
			local RNG = Random.new()
			local DataLen = 1024
			local PieceCount = 32

			local Data = buffer.create(DataLen)
			for I = 0, DataLen - 1 do
				buffer.writeu8(Data, I, RNG:NextInteger(0, 255))
			end

			local Enc = Encoder.New(Data, PieceCount) :: RLNC.Encoder
			local FullLen = Enc:GetFullCodedPieceByteLen()

			local NumPieces = PieceCount // 2
			local CodedPieces = buffer.create(NumPieces * FullLen)
			for I = 0, NumPieces - 1 do
				local Piece = Enc:Code(RNG)
				buffer.copy(CodedPieces, I * FullLen, Piece, 0, FullLen)
			end

			local Rec = Recoder.New(CodedPieces, FullLen, PieceCount) :: RLNC.Recoder

			local ShortBuffer = buffer.create(FullLen - 1)
			Testing.Expect(Rec:RecodeWithBuffer(ShortBuffer, RNG)).ToBe(RLNCError.InvalidOutputBuffer)

			local LongBuffer = buffer.create(FullLen + 1)
			Testing.Expect(Rec:RecodeWithBuffer(LongBuffer, RNG)).ToBe(RLNCError.InvalidOutputBuffer)

			local EmptyBuffer = buffer.create(0)
			Testing.Expect(Rec:RecodeWithBuffer(EmptyBuffer, RNG)).ToBe(RLNCError.InvalidOutputBuffer)

			local ValidBuffer = buffer.create(FullLen)
			Testing.Expect(Rec:RecodeWithBuffer(ValidBuffer, RNG)).ToBeNil()
		end)

		Testing.Test("getters", function()
			local RNG = Random.new()
			local DataLen = 1024
			local PieceCount = 32

			local Data = buffer.create(DataLen)
			for I = 0, DataLen - 1 do
				buffer.writeu8(Data, I, RNG:NextInteger(0, 255))
			end

			local Enc = Encoder.New(Data, PieceCount) :: RLNC.Encoder
			local FullLen = Enc:GetFullCodedPieceByteLen()
			local PieceByteLen = Enc:GetPieceByteLen()

			local NumPieces = 10
			local CodedPieces = buffer.create(NumPieces * FullLen)
			for I = 0, NumPieces - 1 do
				local Piece = Enc:Code(RNG)
				buffer.copy(CodedPieces, I * FullLen, Piece, 0, FullLen)
			end

			local Rec = Recoder.New(CodedPieces, FullLen, PieceCount) :: RLNC.Recoder

			Testing.Expect(Rec:GetOriginalNumPiecesCodedTogether()).ToBe(PieceCount)
			Testing.Expect(Rec:GetNumPiecesRecodedTogether()).ToBe(NumPieces)
			Testing.Expect(Rec:GetPieceByteLen()).ToBe(PieceByteLen)
			Testing.Expect(Rec:GetFullCodedPieceByteLen()).ToBe(FullLen)
		end)
	end)

	Testing.Describe("RLNC Integration", function()
		Testing.Test("prop_test_encoder_decoder", function()
			local NumIterations = 10
			local MinDataLen, MaxDataLen = 1024, 65536
			local MinPieceCount, MaxPieceCount = 32, 256
			local RNG = Random.new()

			for _ = 1, NumIterations do
				local DataLen = RNG:NextInteger(MinDataLen, MaxDataLen)
				local PieceCount = RNG:NextInteger(MinPieceCount, MaxPieceCount)

				local Data = buffer.create(DataLen)
				for I = 0, DataLen - 1 do
					buffer.writeu8(Data, I, RNG:NextInteger(0, 255))
				end
				local DataCopy = buffer.create(DataLen)
				buffer.copy(DataCopy, 0, Data, 0, DataLen)

				local Enc = Encoder.New(Data, PieceCount) :: RLNC.Encoder
				local Dec = Decoder.New(Enc:GetPieceByteLen(), Enc:GetPieceCount()) :: RLNC.Decoder

				while true do
					local Piece = Enc:Code(RNG)
					local Result = Dec:Decode(Piece)

					if Result == RLNCError.ReceivedAllPieces then
						break
					elseif Result == RLNCError.PieceNotUseful then
						continue
					elseif Result ~= nil then
						error(`Unexpected error: {Result}`)
					end
				end

				Testing.Expect(Dec:IsAlreadyDecoded()).ToBe(true)

				local Decoded = Dec:GetDecodedData() :: buffer
				Testing.Expect(buffer.tostring(Decoded)).ToBe(buffer.tostring(DataCopy))
			end
		end)

		Testing.Test("prop_test_encoder_recoder_decoder", function()
			local NumIterations = 10
			local MinDataLen, MaxDataLen = 1024, 16384
			local MinPieceCount, MaxPieceCount = 32, 128
			local MinRecodePieces, MaxRecodePieces = 2, 64
			local RNG = Random.new()

			for _ = 1, NumIterations do
				local DataLen = RNG:NextInteger(MinDataLen, MaxDataLen)
				local PieceCount = RNG:NextInteger(MinPieceCount, MaxPieceCount)

				local Data = buffer.create(DataLen)
				for I = 0, DataLen - 1 do
					buffer.writeu8(Data, I, RNG:NextInteger(0, 255))
				end
				local DataCopy = buffer.create(DataLen)
				buffer.copy(DataCopy, 0, Data, 0, DataLen)

				local Enc = Encoder.New(Data, PieceCount) :: RLNC.Encoder
				local Dec = Decoder.New(Enc:GetPieceByteLen(), Enc:GetPieceCount()) :: RLNC.Decoder
				local FullLen = Enc:GetFullCodedPieceByteLen()

				while true do
					local NumPiecesToRecode = RNG:NextInteger(MinRecodePieces, MaxRecodePieces)
					local CodedPieces = buffer.create(NumPiecesToRecode * FullLen)

					for I = 0, NumPiecesToRecode - 1 do
						local Piece = Enc:Code(RNG)
						buffer.copy(CodedPieces, I * FullLen, Piece, 0, FullLen)
					end

					local Rec = Recoder.New(CodedPieces, FullLen, Enc:GetPieceCount()) :: RLNC.Recoder

					local NumRecodedToUse = RNG:NextInteger(1, 50)
					for _ = 1, NumRecodedToUse do
						local RecodedPiece = Rec:Recode(RNG)
						local Result = Dec:Decode(RecodedPiece)

						if Result == RLNCError.ReceivedAllPieces then
							break
						end
					end

					if Dec:IsAlreadyDecoded() then
						break
					end

					local DirectPiece = Enc:Code(RNG)
					local Result = Dec:Decode(DirectPiece)

					if Result == RLNCError.ReceivedAllPieces then
						break
					end
				end

				Testing.Expect(Dec:IsAlreadyDecoded()).ToBe(true)

				local Decoded = Dec:GetDecodedData() :: buffer
				Testing.Expect(buffer.tostring(Decoded)).ToBe(buffer.tostring(DataCopy))
			end
		end)

		Testing.Test("prop_test_decoding_with_useless_pieces", function()
			local NumIterations = 10
			local MinDataLen, MaxDataLen = 1024, 16384
			local MinPieceCount, MaxPieceCount = 32, 128
			local RNG = Random.new()

			for _ = 1, NumIterations do
				local DataLen = RNG:NextInteger(MinDataLen, MaxDataLen)
				local PieceCount = RNG:NextInteger(MinPieceCount, MaxPieceCount)

				local Data = buffer.create(DataLen)
				for I = 0, DataLen - 1 do
					buffer.writeu8(Data, I, RNG:NextInteger(0, 255))
				end
				local DataCopy = buffer.create(DataLen)
				buffer.copy(DataCopy, 0, Data, 0, DataLen)

				local Enc = Encoder.New(Data, PieceCount) :: RLNC.Encoder
				local Dec = Decoder.New(Enc:GetPieceByteLen(), Enc:GetPieceCount()) :: RLNC.Decoder
				local FullLen = Enc:GetFullCodedPieceByteLen()

				local NumPiecesForRecoding = PieceCount // 2
				local CodedPiecesForRecoding = buffer.create(NumPiecesForRecoding * FullLen)
				local ActualUseful = 0

				for I = 0, NumPiecesForRecoding - 1 do
					local Piece = Enc:Code(RNG)
					local Result = Dec:Decode(Piece)
					if Result == nil then
						buffer.copy(CodedPiecesForRecoding, ActualUseful * FullLen, Piece, 0, FullLen)
						ActualUseful += 1
					end
				end

				if ActualUseful < 2 then
					continue
				end

				local TrimmedPieces = buffer.create(ActualUseful * FullLen)
				buffer.copy(TrimmedPieces, 0, CodedPiecesForRecoding, 0, ActualUseful * FullLen)

				local Rec = Recoder.New(TrimmedPieces, FullLen, Enc:GetPieceCount()) :: RLNC.Recoder

				local NumRecodedToTry = ActualUseful * 2
				for _ = 1, NumRecodedToTry do
					local RecodedPiece = Rec:Recode(RNG)
					local Result = Dec:Decode(RecodedPiece)

					Testing.Expect(Result).Never.ToBeNil()
					if Result ~= RLNCError.PieceNotUseful then
						Testing.Expect(Result).ToBe(RLNCError.ReceivedAllPieces)
					end
				end

				while Dec:GetRemainingPieceCount() > 0 do
					local Piece = Enc:Code(RNG)
					local Result = Dec:Decode(Piece)

					if Result == RLNCError.PieceNotUseful then
						continue
					elseif Result ~= nil and Result ~= RLNCError.ReceivedAllPieces then
						error(`Unexpected error: {Result}`)
					end
				end

				Testing.Expect(Dec:IsAlreadyDecoded()).ToBe(true)

				local Decoded = Dec:GetDecodedData() :: buffer
				Testing.Expect(buffer.tostring(Decoded)).ToBe(buffer.tostring(DataCopy))
			end
		end)

		Testing.Test("single_piece_encoding", function()
			local RNG = Random.new()
			local Data = buffer.fromstring("Hello, World!")
			local DataCopy = buffer.fromstring("Hello, World!")

			local Enc = Encoder.New(Data, 1) :: RLNC.Encoder
			local Dec = Decoder.New(Enc:GetPieceByteLen(), 1) :: RLNC.Decoder

			local Piece = Enc:Code(RNG)
			local Result = Dec:Decode(Piece)

			Testing.Expect(Dec:IsAlreadyDecoded()).ToBe(true)

			local Decoded = Dec:GetDecodedData() :: buffer
			Testing.Expect(buffer.tostring(Decoded)).ToBe(buffer.tostring(DataCopy))
		end)

		Testing.Test("minimum_data_encoding", function()
			local RNG = Random.new()
			local Data = buffer.fromstring("X")
			local DataCopy = buffer.fromstring("X")

			local Enc = Encoder.New(Data, 1) :: RLNC.Encoder
			local Dec = Decoder.New(Enc:GetPieceByteLen(), 1) :: RLNC.Decoder

			local Piece = Enc:Code(RNG)
			Dec:Decode(Piece)

			Testing.Expect(Dec:IsAlreadyDecoded()).ToBe(true)

			local Decoded = Dec:GetDecodedData() :: buffer
			Testing.Expect(buffer.tostring(Decoded)).ToBe(buffer.tostring(DataCopy))
		end)

		Testing.Test("received_all_pieces_error", function()
			local RNG = Random.new()
			local Data = buffer.fromstring("Test data for RLNC")

			local Enc = Encoder.New(Data, 4) :: RLNC.Encoder
			local Dec = Decoder.New(Enc:GetPieceByteLen(), 4) :: RLNC.Decoder

			while not Dec:IsAlreadyDecoded() do
				local Piece = Enc:Code(RNG)
				local Result = Dec:Decode(Piece)
				if Result == RLNCError.ReceivedAllPieces then
					break
				end
			end

			local ExtraPiece = Enc:Code(RNG)
			Testing.Expect(Dec:Decode(ExtraPiece)).ToBe(RLNCError.ReceivedAllPieces)
		end)

		Testing.Test("not_all_pieces_received_yet_error", function()
			local RNG = Random.new()
			local Data = buffer.fromstring("Test data for RLNC")

			local Enc = Encoder.New(Data, 4) :: RLNC.Encoder
			local Dec = Decoder.New(Enc:GetPieceByteLen(), 4) :: RLNC.Decoder

			local Piece = Enc:Code(RNG)
			Dec:Decode(Piece)

			Testing.Expect(Dec:IsAlreadyDecoded()).ToBe(false)

			local Result, Error = Dec:GetDecodedData()
			Testing.Expect(Result).ToBeNil()
			Testing.Expect(Error).ToBe(RLNCError.NotAllPiecesReceivedYet)
		end)
	end)
end)

return 0