
PROJECT = "sc16is752_i2c_min"
VERSION = "1.0.0"
sys = require("sys")
local bit = bit

-- === 用户根据硬件修改这两项 ===
local I2C_ID   = 1
local DEV7BIT  = 0x4D      -- 7bit 器件地址：例如 A1=A0=VDD 时 8bit=0x90 → 7bit=0x48（见手册地址表）

-- 常用寄存器号（手册里的 A[3:0]）
local REG = {
  RHR = 0x00, THR = 0x00,  -- 读RHR/写THR 同地址
  IER = 0x01,
  FCR = 0x02, IIR = 0x02,
  LCR = 0x03,
  MCR = 0x04,
  LSR = 0x05,
  TXLVL = 0x08,
  RXLVL = 0x09,
  DLL = 0x00, DLH = 0x01   -- 需 LCR[7]=1 (DLAB) 时有效
}

-- 生成 I2C 子地址字节：reg=0..15, ch="A"/"B"
local function subaddr(reg, ch)
  local chbits = (ch == "B") and 1 or 0
  return bit.bor(bit.lshift(bit.band(reg, 0x0F), 3), bit.lshift(chbits, 1))
end

-- 写 1 字节寄存器：send( 子地址 + 数据 )
local function wr1(ch, reg, val)
  return i2c.send(I2C_ID, DEV7BIT, string.char(subaddr(reg, ch), bit.band(val, 0xFF)))  -- (I2C号，I2C地址，‘寄存器地址，通道A/B，数据’)
end

-- 读 1 字节寄存器：先发子地址，再 recv(1)
local function rd1(ch, reg)
  i2c.send(I2C_ID, DEV7BIT, string.char(subaddr(reg, ch)))
  local s = i2c.recv(I2C_ID, DEV7BIT, 1)
  return s and string.byte(s) or 0
end

-- 连续写 FIFO（比如 THR）：send( 子地址 + 数据串 )
local function wr_fifo(ch, reg, data_str)
  return i2c.send(I2C_ID, DEV7BIT, string.char(subaddr(reg, ch)) .. data_str)
end

-- 连续读 FIFO（比如 RHR）：send(子地址) → recv(n)
local function rd_fifo(ch, reg, n)
  i2c.send(I2C_ID, DEV7BIT, string.char(subaddr(reg, ch)))
  return i2c.recv(I2C_ID, DEV7BIT, n)
end

-- 设置波特率：xtal=外部晶振(常见 1.8432MHz)，baud=115200 等
-- divisor = round(xtal / (16*baud))
--[[
波特率与分频系数对照表
    波特率    分频值
    2400    48
    3600    32
    4800    24
    7200    16
    9600    12
    19200   6
]]

local function set_baud(ch, xtal, baud)
  local div = 12--9600                           --math.floor((xtal / (16 * baud)) + 0.5)
  if div < 1 then div = 1 end
  local lcr = rd1(ch, REG.LCR)
  wr1(ch, REG.LCR, bit.bor(lcr, 0x80))           -- DLAB=1
  wr1(ch, REG.DLL, bit.band(div, 0xFF))
  wr1(ch, REG.DLH, bit.rshift(div, 8))
  wr1(ch, REG.LCR, bit.band(lcr, 0x7F))          -- 还原 DLAB=0
end

-- 设置 8N1（8位、无校验、1停止位）
local function set_8N1(ch)
  wr1(ch, REG.LCR, 0x03)
end

-- 使能并复位 FIFO（FCR bit0/1/2）
local function fifo_on(ch)
  wr1(ch, REG.FCR, 0x07)
  sys.wait(1) -- 手册建议复位后等待≥2*Tclk 再碰 RHR/THR
end

-- 可选：使能内部回环做自检（MCR[4]）
local function loopback(ch, on)
  local m = rd1(ch, REG.MCR)
  if on then m = bit.bor(m, 0x10) else m = bit.band(m, 0xEF) end
  wr1(ch, REG.MCR, m)
end

sys.taskInit(function()
  log.info("i2c.setup", i2c.setup(I2C_ID))

  -- === 最小初始化：A通道，8N1 + FIFO + 115200 ===
  local CH = "A"
  set_8N1(CH)
  fifo_on(CH)
  set_baud(CH, 1843200, 9600)   -- 若板上是 1.8432MHz，就用 1843200

  -- === “像24C02那样”的 send→wait→recv 用法示例（回环测试）===
  -- loopback(CH, true)              -- 开回环，这样发出的会从自己RX收到

  -- 发送（THR=寄存器0x00）：子地址+数据；和你的 24C02 写法结构一致
  i2c.send(I2C_ID, DEV7BIT, string.char(subaddr(REG.THR, CH)) .. "123456789055")
  sys.wait(100)

  -- 接收（RHR=寄存器0x00）：先发子地址，再读 8 字节
  i2c.send(I2C_ID, DEV7BIT, string.char(subaddr(REG.RHR, CH)))
  local data = i2c.recv(I2C_ID, DEV7BIT, 12)
  log.info("i2c", "rx", data and data:toHex() or "nil", data or "nil")

  -- loopback(CH, false)

  while true do 


    i2c.send(I2C_ID, DEV7BIT, string.char(subaddr(REG.RHR, CH)))
    local data = i2c.recv(I2C_ID, DEV7BIT, 12)
    log.info("i2c", "rx", data and data:toHex() or "nil", data or "nil")
    sys.wait(1000)
  
  
  end
end)

sys.run()
