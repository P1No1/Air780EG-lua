-- 752.lua — SC16IS752 I2C 驱动（A/B 双通道）
-- 封装寄存器与常用读写/配置接口；不创建任务

local bit = bit

local M = {}

-- 常用寄存器号（手册里的 A[3:0]）
M.REG = {
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

-- 工具：生成 I2C 子地址字节：reg=0..15, ch="A"/"B"
local function subaddr(reg, ch)
  local chbits = (ch == "B") and 1 or 0
  return bit.bor(bit.lshift(bit.band(reg, 0x0F), 3), bit.lshift(chbits, 1))
end

-- 构造实例：绑定 I2C 总线与 7bit 器件地址
function M.new(i2c_id, addr7bit)
  local self = {
    i2c_id = i2c_id,
    addr   = addr7bit,
  }

    self.REG = M.REG

  -- 写 1 字节寄存器
  function self:wr1(ch, reg, val)
    return i2c.send(self.i2c_id, self.addr,
      string.char(subaddr(reg, ch), bit.band(val, 0xFF)))
  end

  -- 读 1 字节寄存器
  function self:rd1(ch, reg)
    i2c.send(self.i2c_id, self.addr, string.char(subaddr(reg, ch)))
    local s = i2c.recv(self.i2c_id, self.addr, 1)
    return s and string.byte(s) or 0
  end

  -- 连续写 FIFO（比如 THR）
  function self:wr_fifo(ch, reg, data_str)
    return i2c.send(self.i2c_id, self.addr,
      string.char(subaddr(reg, ch)) .. data_str)
  end

  -- 连续读 FIFO（比如 RHR）
  function self:rd_fifo(ch, reg, n)
    i2c.send(self.i2c_id, self.addr, string.char(subaddr(reg, ch)))
    return i2c.recv(self.i2c_id, self.addr, n)
  end

  -- 设置 8N1（8位、无校验、1停止位）
  function self:set_8N1(ch)
    self:wr1(ch, M.REG.LCR, 0x03)
  end

  -- 使能并复位 FIFO（FCR bit0/1/2）
  function self:fifo_on(ch)
    self:wr1(ch, M.REG.FCR, 0x07)
    sys.wait(1) -- 手册建议复位后等待≥2*Tclk 再碰 RHR/THR
  end

  -- 可选：内部回环自检（MCR[4]=1 开启）
  function self:loopback(ch, on)
    local m = self:rd1(ch, M.REG.MCR)
    if on then m = bit.bor(m, 0x10) else m = bit.band(m, 0xEF) end
    self:wr1(ch, M.REG.MCR, m)
  end

  -- 设置波特率：xtal=外部晶振(如 1.8432MHz)，baud=115200 等
  -- 这里沿用示例中的固定分频 12 → 9600bps；若要公式计算请改为注释行
  function self:set_baud(ch, xtal, baud)
    local div = 12 -- math.floor((xtal / (16 * baud)) + 0.5)
    if div < 1 then div = 1 end
    local lcr = self:rd1(ch, M.REG.LCR)
    self:wr1(ch, M.REG.LCR, bit.bor(lcr, 0x80))           -- DLAB=1
    self:wr1(ch, M.REG.DLL, bit.band(div, 0xFF))
    self:wr1(ch, M.REG.DLH, bit.rshift(div, 8))
    self:wr1(ch, M.REG.LCR, bit.band(lcr, 0x7F))          -- 还原 DLAB=0
  end

  return self
end

return M
