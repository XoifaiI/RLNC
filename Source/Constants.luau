--[=[
	RLNCConstants: Constants for Random Linear Network Coding
	
	Boundary Marker:
		To make sure that any RLNC coded data gets decoded correctly, append
		a 1-byte boundary marker followed by N >= 0 zero bytes to make all
		data chunks equal sized.
		
		At decoding time, the boundary marker determines how far the original
		data extends. Once encountered, zero or more zero bytes may follow,
		determined by the original data length and number of chunks.
	
	Return type: Module table with RLNC constants
	
	Example usage:
		local RLNCConstants = require(path.to.RLNCConstants)
		
		buffer.writeu8(PaddedData, OriginalLength, RLNCConstants.BOUNDARY_MARKER)
--]=]

--!strict
--!optimize 2

return {
	BOUNDARY_MARKER = 0x81,
}
