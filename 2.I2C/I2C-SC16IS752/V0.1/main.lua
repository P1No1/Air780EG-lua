-- Lua port of the SC16IS752 I2C UART bridge example
-- Wiring:
--   Connect CH-A TX -> CH-B RX
--   Connect CH-B TX -> CH-A RX



PROJECT = "sc16is752_i2c_min"
VERSION = "0.0.9"
sys = require("sys")
local bit = bit

-- === 用户根据硬件修改这两项 ===移植
-- local I2C_ID   = 1
-- local I2C_ADDR  = 0x4D      -- 7bit 器件地址：例如 A1=A0=VDD 时 8bit=0x90 → 7bit=0x48（见手册地址表）



local sc16is752 = require("sc16is752")

-- 按你的实际硬件改：I2C 引脚与 7-bit 地址
local I2C_BUS = 1
local SDA_PIN = 2   -- 示例：GPIO2
local SCL_PIN = 1   -- 示例：GPIO1
local I2C_ADDR = 0x4A  -- 对应 Arduino 的 ADDRESS_AA（示例值，按你芯片焊接地址位改）

-- 创建设备实例（假定模块提供 new/ setupI2C 之类接口）
local i2cuart = sc16is752.new({
  bus  = I2C_BUS,
  sda  = SDA_PIN,
  scl  = SCL_PIN,
  addr = I2C_ADDR
})

local function setup()
  -- 串口调试输出（NodeMCU：UART0）
  if uart and uart.setup then
    uart.setup(0, 115200, 8, 0, 1, 1)
  end

  print("Start testing")

  -- 双通道波特率初始化（与原示例等价）
  i2cuart:begin(9600, 9600)

  if i2cuart:ping() ~= 1 then
    print("Device not found")
    while true do end
  else
    print("Device found")
  end

  print("Start serial communication")
end

local function loop()
  while true do
    -- A 通道发 0x55，B 通道收
    i2cuart:write("A", 0x55)

    -- 10ms 延时
    if tmr and tmr.delay then
      tmr.delay(0, 10000)         -- NodeMCU：tmr.delay(id, microseconds)
    else
      -- 纯 Lua 备用：约 10ms 忙等
      local t = os.clock() + 0.01
      while os.clock() < t do end
    end

    if i2cuart:available("B") == 0 then
      print("Please connnect CH-A TX and CH-B RX with a wire and reset your board")
      while true do end
    end
    if i2cuart:read("B") ~= 0x55 then
      print("Serial communication error")
      while true do end
    end

    -- 200ms 延时
    if tmr and tmr.delay then
      tmr.delay(0, 200000)
    else
      local t = os.clock() + 0.2
      while os.clock() < t do end
    end

    -- B 通道发 0xAA，A 通道收
    i2cuart:write("B", 0xAA)

    if tmr and tmr.delay then
      tmr.delay(0, 10000)
    else
      local t = os.clock() + 0.01
      while os.clock() < t do end
    end

    if i2cuart:available("A") == 0 then
      print("Please connnect CH-B TX and CH-A RX with a wire and reset your board")
      while true do end
    end
    if i2cuart:read("A") ~= 0xAA then
      print("Serial communication error")
      while true do end
    end

    if tmr and tmr.delay then
      tmr.delay(0, 200000)
    else
      local t = os.clock() + 0.2
      while os.clock() < t do end
    end
  end
end

setup()
loop()
