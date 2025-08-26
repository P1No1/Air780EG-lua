PROJECT = "sc16is752_i2c_min"
VERSION = "2.0.1"

sys = require("sys")
local bit = bit
local sc752 = require("752")   -- 引用驱动

-- === I2C修改这两项 ===
local I2C_ID   = 1
local DEV7BIT  = 0x4D          -- 7bit 器件地址

sys.taskInit(function()
  log.info("i2c.setup", i2c.setup(I2C_ID))

  -- 创建 752 实例并做最小初始化：A 通道，8N1 + FIFO + 9600
  local uart = sc752.new(I2C_ID, DEV7BIT)
  local CH = "A"
  uart:set_8N1(CH)
  uart:fifo_on(CH)
  uart:set_baud(CH, 1843200, 9600)  -- 若板上是 1.8432MHz，就用 1843200；当前固定为 9600


  
  local CH2 = "B"
  uart:set_8N1(CH2)
  uart:fifo_on(CH2)
  uart:set_baud(CH2, 1843200, 9600)  -- 若板上是 1.8432MHz，就用 1843200；当前固定为 9600



  -- 一次性演示：发送 0xD2（温湿度被动模式-4B），再读回4字节
  local cmd_2 = string.char(0xD6)


  uart:wr_fifo(CH, uart.REG.THR, cmd_2)
  sys.wait(100)
  local data = uart:rd_fifo(CH, uart.REG.RHR, 4)
  log.info("i2c", "rx", data and data:toHex() or "nil", data or "nil")

  -- 循环轮询示例：每秒读一次温度（前两字节为温度，单位 0.01°C，假设大端）
  while true do
    uart:wr_fifo(CH , uart.REG.THR, cmd_2)
    uart:wr_fifo(CH2, uart.REG.THR, cmd_2)
    sys.wait(200)
    local d = uart:rd_fifo(CH, uart.REG.RHR, 6)
    local d2 = uart:rd_fifo(CH2, uart.REG.RHR, 14)

    local bA1, bA2 = string.byte(d, 1, 2)
    local num1 = (bA1 << 8) | bA2

    local bB1, bB2 = string.byte(d2, 1, 2)
    local num2 = (bB1 << 8) | bB2

    if num1 >= 1 and num1 ~= 2570  then
      
      log.info("i2c"..I2C_ID.."--uart"..CH, "温度=" .. string.format("%.2f", num1/100) .. "°C",d:toHex(),d2:toHex())
      uart:wr_fifo(CH, uart.REG.FCR, 0x03)
      uart:wr_fifo(CH2, uart.REG.FCR, 0x03)

    elseif num2 >= 1 and num2 ~= 2570 then
      
      log.info("i2c"..I2C_ID.."--uart"..CH2, "温度=" .. string.format("%.2f", num2/100) .. "°C",d:toHex(),d2:toHex())
      uart:wr_fifo(CH, uart.REG.FCR, 0x03)
      uart:wr_fifo(CH2, uart.REG.FCR, 0x03)
    else
      log.warn("i2c", "no data")
    end

    sys.wait(800)
  end
end)

sys.run()



-- 08/20/14:22：如果温度真的是0怎么办