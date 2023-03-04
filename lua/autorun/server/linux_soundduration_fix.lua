-- Patch/relplacement for the global SoundDuration function for servers that are not running on Windows (i.e. running on Linux or macOS).
-- Non-windows servers don't know how to get the length of .wav files and will just return 0 for the length, which messes with logic based on sound length,
-- particularly E2 stuff in Sandbox.
--  - If on Windows, this will use the standard SoundDuration function, since it works on Windows just fine
--  - On Linux, since SoundDuration returns 0, it reads the header and returns DataLen/(SampleRate * NumChannels * BitsPerSample/8) as the length in seconds
-- Denominator is encoded in header as ByteRate (ULong at offset 28)
-- Returns 0 if: (Windows: SoundDuration returns nil or 0), (Linux/Mac: file is locked, file length is less than 44 bytes, or if ByteRate or DataLen was 0)
-- Will revert to the imprecise method of file:Size() - 44 if the length from the header looks wrong

local bit = bit
local file = file
local string = string

-- offsets for wav header 
local WAV_OFFSET_BYTERATE = 28 -- SampleRate * NumChannels * BitsPerSample/8
local WAV_OFFSET_SUBCHUNK1SIZE = 16 -- =0x0F for PCM
local WAV_OFFSET_SUBCHUNK2SIZE = 40 -- If PCM, 40. Else, need to offset by + (SubChunk1Size - 4)

-- remove stupid characters from a filepath
local normPath = function(path)
    return path:Trim():gsub("\\", "/")
end

-- read 4 bytes and return number value (little-endian)
local read4 = function(f, offset)
    if f == nil then return 0 end
    local br = {0,0,0,0}
    f:Seek(offset)
    local i
    for i = 1, 4 do 
        if not f:EndOfFile() then br[i] = f:ReadByte() else br[i] = 0 end
    end
    return bit.lshift(br[4], 24) + bit.lshift(br[3], 16) + bit.lshift(br[2], 8) + br[1]
end

-- calculates the length of the wav
local wavLen = function(path)
    f = file.Open(path, "rb", "GAME")
    if f == nil then return 0 end
    if f:Size() < 44 then return 0 end
    local SubChunk1Size = read4(f, WAV_OFFSET_SUBCHUNK1SIZE)
    local ByteRate = read4(f, WAV_OFFSET_BYTERATE)
    if ByteRate == 0 then f:Close() return 0 end
    local DataLen = read4(f, WAV_OFFSET_SUBCHUNK2SIZE + (SubChunk1Size == 16 and 0 or SubChunk1Size - 4))
    if DataLen <= 64 then DataLen = f:Size() - 44 end -- odd edge case found in an addon I can't rememeber
    f:Close()
    return DataLen / ByteRate
end

local oldSoundDuration = SoundDuration
if not system.IsWindows() then
    SoundDuration = function(path)
        if string.sub(path, -4) ~= ".wav" then return oldSoundDuration(path) or 0 end
        if path:match('["?]') then return 0 end -- POSIX-friendly
        path = normPath(path)
        if string.sub(path, 1, 6) ~= "sound/" then path = "sound/" .. path end
        return wavLen(path)
    end
end
