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

  -- 创建 UART 实例并做初始化
  local uart = sc752.new(I2C_ID, DEV7BIT)
  
  -- 配置通道 A 和 B
  local function setup_uart(channel)
    uart:set_8N1(channel)          -- 8N1 配置
    uart:fifo_on(channel)          -- 开启 FIFO 缓冲区
    uart:set_baud(channel, 1843200, 9600)  -- 设置波特率
  end
  
  setup_uart("A")
  setup_uart("B")

  -- 命令字节（温湿度被动模式-4B）
  local cmd_2 = string.char(0xD6)

  -- 一次性发送命令并读取数据的函数
  local function read_data(channel)
    uart:wr_fifo(channel, uart.REG.THR, cmd_2)  -- 发送命令
    sys.wait(200)  -- 等待响应

    -- 读取数据
    local data = uart:rd_fifo(channel, uart.REG.RHR, 200)
    return data
  end

  -- 处理和格式化数据
  local function process_data(data, channel)
    if not data then
      log.warn("i2c", "no data received on channel " .. channel)
      return
    end

    -- 解析数据字节
    
    local pm25_low = string.byte(data, 2)  -- PM2.5 低字节
    local pm25_high = string.byte(data, 1)   -- PM2.5 高字节
    local pm10_low = string.byte(data, 4)  -- PM10 低字节
    local pm10_high = string.byte(data, 3)   -- PM10 高字节
    -- 计算 PM2.5 和 PM10 值
    local pm25 = (pm25_high * 256 + pm25_low) / 100
    local pm10 = (pm10_high * 256 + pm10_low) / 100

    -- 检查有效性
    if pm25 >= 1 and pm25 ~= 2570 then
      return pm25, pm10
    else
      log.warn("i2c", "Invalid data received on channel " .. channel)
      return nil, nil
    end
  end

  local function process_data_2(data, channel)  -- 计算PM2.5改为温湿度
    if not data then
      log.warn("i2c", "no data received on channel " .. channel)
      return
    end

    -- 解析数据字节
    local pm25_high = string.byte(data, 5)  -- 温度 高字节
    local pm25_low = string.byte(data, 4)   -- 温度 低字节
    local pm10_high = string.byte(data, 3)  -- 湿度 高字节
    local pm10_low = string.byte(data, 4)   -- 湿度 低字节

    -- 计算 温度 和 湿度 值
    local pm25 = (pm25_high * 256 + pm25_low) / 10
    local pm10 = (pm10_high * 256 + pm10_low) / 10

    -- 检查有效性
    if pm25 >= 1 and pm25 ~= 2570 then
      return pm25, pm10
    else
      log.warn("i2c", "Invalid data received on channel " .. channel)
      return nil, nil
    end
  end
  -- 循环读取并输出数据
  while true do
    -- 读取通道 A 数据
    local dataA = read_data("A")
    local pm25A, pm10A = process_data(dataA, "A")

    -- 读取通道 B 数据
    local dataB = read_data("B")
    local pm25B, pm10B = process_data_2(dataB, "B")

    -- 显示 温度 和 湿度 数据（通道 A）
    if pm25A then
      log.info("i2c"..I2C_ID.."--uartA", "温度 = " .. string.format("%.2f", pm25A) .. " °C, 湿度 = " .. string.format("%.2f", pm10A) .. " %")
    end

    -- 显示 PM2.5 和 PM10 数据（通道 B）
    if pm25B then
      log.info("i2c"..I2C_ID.. dataB:toHex())
    end

    -- 延时 800ms 后继续读取
    sys.wait(2000)
  end
end)

sys.run()
