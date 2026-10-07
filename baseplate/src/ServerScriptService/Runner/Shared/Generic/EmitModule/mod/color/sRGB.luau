--[[
MIT License

Copyright (c) 2024 Daniel P H Fox

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]

--!strict
--!nolint LocalUnused
--!nolint LocalShadow
local task = nil

local sRGB = {}

local function transform(channel: number): number
  if channel >= 0.04045 then
    return ((channel + 0.055) / (1 + 0.055)) ^ 2.4
  else
    return channel / 12.92
  end
end

local function inverse(channel: number): number
  if channel >= 0.0031308 then
    return 1.055 * channel ^ (1.0 / 2.4) - 0.055
  else
    return 12.92 * channel
  end
end

function sRGB.fromLinear(rgb: Color3): Color3
  return Color3.new(transform(rgb.R), transform(rgb.G), transform(rgb.B))
end

function sRGB.toLinear(srgb: Color3): Color3
  return Color3.new(inverse(srgb.R), inverse(srgb.G), inverse(srgb.B))
end

return sRGB