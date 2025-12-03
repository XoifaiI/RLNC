# RLNC - Random Linear Network Coding for Luau

Erasure coding library for reliable data transmission over lossy channels. Designed for Roblox's MessagingService where packet loss is common.

## What is RLNC?

Random Linear Network Coding splits your data into pieces and creates coded combinations using random coefficients over GF(256). The receiver only needs *any* `k` linearly independent pieces to reconstruct the original data, it doesn't matter which ones arrive or in what order.

This makes it ideal for unreliable channels where packets can be dropped, duplicated, or reordered.

## Installation

Copy the RLNC folder into your project and require the init module:

```lua
local RLNC = require(path.to.RLNC)
```

## Quick Start

```lua
local RLNC = require(path.to.RLNC)

-- Original data
local Data = buffer.fromstring("Hello, World!")
local PieceCount = 4

-- Encode
local Encoder = RLNC.Encoder.New(Data, PieceCount)

-- Create decoder
local Decoder = RLNC.Decoder.New(Encoder:GetPieceByteLen(), PieceCount)

-- Generate and feed coded pieces until decoded
local RNG = Random.new()
while not Decoder:IsAlreadyDecoded() do
    local CodedPiece = Encoder:Code(RNG)
    Decoder:Decode(CodedPiece)
end

-- Recover original data
local Recovered = Decoder:GetDecodedData()
print(buffer.tostring(Recovered)) -- "Hello, World!"
```

## Practical Example: Reliable MessagingService

MessagingService has "best effort" delivery, packets can be dropped. RLNC fixes this:

```lua
local RLNC = require(path.to.RLNC)
local MessagingService = game:GetService("MessagingService")

local PIECE_COUNT = 8
local REDUNDANCY = 1.5 -- Send 50% extra pieces

-- Sender
local function PublishReliable(Topic: string, Data: buffer)
    local Encoder = RLNC.Encoder.New(Data, PIECE_COUNT)
    local TotalPieces = math.ceil(PIECE_COUNT * REDUNDANCY)
    local RNG = Random.new()
    
    for i = 1, TotalPieces do
        local CodedPiece = Encoder:Code(RNG)
        MessagingService:PublishAsync(Topic, buffer.tostring(CodedPiece))
    end
end

-- Receiver
local Decoders = {}

local function OnMessage(MessageId: string, PieceByteLen: number, CodedPiece: buffer)
    local Decoder = Decoders[MessageId]
    if not Decoder then
        Decoder = RLNC.Decoder.New(PieceByteLen, PIECE_COUNT)
        Decoders[MessageId] = Decoder
    end
    
    if Decoder:IsAlreadyDecoded() then
        return nil -- Already have the message
    end
    
    Decoder:Decode(CodedPiece)
    
    if Decoder:IsAlreadyDecoded() then
        Decoders[MessageId] = nil
        return Decoder:GetDecodedData()
    end
    
    return nil -- Need more pieces
end
```

With `REDUNDANCY = 1.5`, you send 12 pieces but only need any 8 to decode. This tolerates up to **33% packet loss**.

| Redundancy | Pieces Sent | Max Packet Loss |
|------------|-------------|-----------------|
| 1.5        | 12          | 33%             |
| 2.0        | 16          | 50%             |
| 3.0        | 24          | 67%             |

## API Reference

### Encoder

```lua
-- Create encoder (auto-pads data)
local Encoder, Error = RLNC.Encoder.New(Data: buffer, PieceCount: number)

-- Create encoder without padding (data length must be divisible by PieceCount)
local Encoder, Error = RLNC.Encoder.WithoutPadding(Data: buffer, PieceCount: number)

Encoder:GetPieceCount() -> number
Encoder:GetPieceByteLen() -> number
Encoder:GetFullCodedPieceByteLen() -> number
Encoder:Code(Random: Random) -> buffer
Encoder:CodeWithBuffer(OutputBuffer: buffer, Random: Random) -> Error?
```

### Decoder

```lua
local Decoder, Error = RLNC.Decoder.New(PieceByteLen: number, PieceCount: number)

Decoder:Decode(CodedPiece: buffer) -> Error?
Decoder:IsAlreadyDecoded() -> boolean
Decoder:GetDecodedData() -> (buffer?, Error?)
Decoder:GetUsefulPieceCount() -> number
Decoder:GetRemainingPieceCount() -> number
```

### Recoder

Re-encode received pieces without decoding, useful for network relays:

```lua
local Recoder, Error = RLNC.Recoder.New(
    ReceivedPieces: buffer,
    FullCodedPieceByteLen: number,
    PieceCount: number
)

Recoder:Recode(Random: Random) -> buffer
```

### Errors

```lua
RLNC.Error.PieceNotUseful      -- Piece was linearly dependent (not an error, just need more)
RLNC.Error.ReceivedAllPieces   -- Already decoded, no more pieces needed
RLNC.Error.NotAllPiecesReceivedYet
RLNC.Error.InvalidPieceLength
RLNC.Error.InvalidDecodedDataFormat
```

## How It Works

1. **Encoding**: Data is padded and split into `k` pieces. Each coded piece is a random linear combination of all original pieces over GF(256).

2. **Transmission**: Send `n > k` coded pieces. Any `k` linearly independent pieces can recover the data.

3. **Decoding**: Received pieces form an augmented matrix. Gaussian elimination (RREF) recovers the original pieces when rank equals `k`.

4. **Recoding** (optional): Intermediate nodes can create new valid coded pieces from received ones without decoding — true network coding.

## License

MIT