--[=[
	RLNC: Random Linear Network Coding Library
	
	Erasure coding for reliable data transmission over lossy channels (MessagingService)
	
	Components:
		Encoder - Splits and encodes original data into coded pieces
		Decoder - Collects coded pieces and recovers original data via Gaussian elimination
		Recoder - Re-encodes received coded pieces without decoding (network coding)
	
	Key Concepts:
		- Original data is padded and split into PieceCount pieces
		- Each coded piece contains a coding vector (coefficients) + coded data
		- Decoder needs PieceCount linearly independent pieces to recover data
		- Recoder can generate new coded pieces from existing ones
	
	Return type: Module table with Encoder, Decoder, Recoder, Error, and Constants
	
	Example usage:
		local RLNC = require(path.to.RLNC)
		
		-- Encode
		local Data = buffer.fromstring(string.rep("Hello World! ", 100))
		local Encoder = RLNC.Encoder.New(Data, 8)
		
		-- Decode
		local Decoder = RLNC.Decoder.New(Encoder:GetPieceByteLen(), Encoder:GetPieceCount())
		local RNG = Random.new()
		
		while not Decoder:IsAlreadyDecoded() do
			local CodedPiece = Encoder:Code(RNG)
			local Error = Decoder:Decode(CodedPiece)
			
			if Error == RLNC.Error.PieceNotUseful then
				-- Linearly dependent, need another piece
			elseif Error then
				warn("Decode error:", RLNC.Error.Message(Error))
			end
		end
		
		local OriginalData = Decoder:GetDecodedData()
--]=]

--!strict

local GF256 = require("@self/GF256")
local RLNCConstants = require("@self/Constants")
local RLNCError = require("@self/Errors")
local RLNCDecoderMatrix = require("@self/DecoderMatrix")
local RLNCEncoder = require("@self/Encoder")
local RLNCDecoder = require("@self/Decoder")
local RLNCRecoder = require("@self/Recoder")

export type Encoder = RLNCEncoder.Encoder
export type Decoder = RLNCDecoder.Decoder
export type Recoder = RLNCRecoder.Recoder
export type DecoderMatrix = RLNCDecoderMatrix.DecoderMatrix
export type RLNCError = RLNCError.RLNCError

return {
	Encoder = RLNCEncoder,
	Decoder = RLNCDecoder,
	Recoder = RLNCRecoder,
	DecoderMatrix = RLNCDecoderMatrix,
	Error = RLNCError,
	Constants = RLNCConstants,
	GF256 = GF256,
}