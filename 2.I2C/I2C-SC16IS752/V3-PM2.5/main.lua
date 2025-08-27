PROJECT = "sc16is752_i2c_min"
VERSION = "2.0.1"

sys = require("sys")
local bit = bit
local sc752 = require("752")   -- 引用驱动

-- === I2C修改这两项 ===
local I2C_ID   = 1

local DEV7BIT  = 0x4D          -- 7bit 器件地址
local DEV7BIT2  = 0x4D


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

  -- 创建 第二个 UART 实例并做初始化
  local uart2 = sc752.new(I2C_ID, DEV7BIT2)
  
  -- 配置通道 A 和 B
  local function setup_uart2(channel)
    uart2:set_8N1(channel)          -- 8N1 配置
    uart2:fifo_on(channel)          -- 开启 FIFO 缓冲区
    uart2:set_baud(channel, 1843200, 9600)  -- 设置波特率
  end
  
  setup_uart2("A")
  setup_uart2("B")







  -- 命令字节（温湿度被动模式-4B）
  local cmd_2 = string.char(0xD6)
  local cmd_active_upload_1 = string.char(0xFF, 0x01, 0x87, 0x00, 0x00, 0x00, 0x00, 0x00, 0x78)  --主动模式-9bit


  -- 一次性发送命令并读取数据的函数
  local function read_T_data(channel)
    uart:wr_fifo(channel, uart.REG.THR, cmd_active_upload_1)  -- 发送命令
    sys.wait(300)  -- 等待响应

    -- 读取数据
    local data = uart:rd_fifo(channel, uart.REG.RHR, 14)
    return data
  end


  local function read_data(channel)
    -- uart:wr_fifo(channel, uart.REG.THR, cmd_2)  -- 发送命令
    -- sys.wait(100)  -- 等待响应

    -- 读取数据
    local data = uart:rd_fifo(channel, uart.REG.RHR, 10)
    return data
  end


  -- 处理和格式化数据


  local function process_data_temp(data, channel)  -- 计算温湿度
    if not data then
      log.warn("i2c", "no degree data received on channel " .. channel)
      return
    end

    -- 解析数据字节
    --local check = string.byte(data, 1)

    local ug_high = string.byte(data, 3)  -- 气体浓度µg/m³ 高字节
    local ug_low = string.byte(data, 4)   -- 气体浓度µg/m³ 低字节
    local max_high = string.byte(data, 5)  -- 满量程 高字节
    local max_low = string.byte(data, 6)   -- 满量程 低字节
    local ppb_high = string.byte(data, 7)  -- 气体浓度ppb 高字节
    local ppb_low = string.byte(data, 8)   -- 气体浓度ppb 低字节

    local temp_high = string.byte(data, 9)  -- 温度 高字节
    local temp_low = string.byte(data, 10)   -- 温度 低字节
    local Rh_high = string.byte(data, 11)  -- 湿度 高字节
    local Rh_low = string.byte(data, 12)   -- 湿度 低字节

    -- 计算值
    local ug = (ug_high * 256 + ug_low) /1.0
    local max = (max_high * 256 +max_low) /1.0
    local ppb = (ppb_high * 256 + ppb_low) /1.0
    
    local temp = (temp_high * 256 + temp_low) / 100
    local Rh = (Rh_high * 256 +Rh_low) / 100

    -- 检查有效性
    if temp >= 1 and temp ~= 2570 then    -- 此判断条件可根据实际情况调整 AAA
      return ug, max, ppb, temp, Rh
    else
      log.warn("i2c", "Invalid data received on channel " .. channel)
      return nil, nil
    end
  end

  local function process_data(data, channel)
    if not data then
      log.warn("i2c", "no air data received on channel " .. channel)
      return
    end

    -- 解析数据字节
    
    local pm25_low = string.byte(data, 3)  -- PM2.5 低字节
    local pm25_high = string.byte(data, 4)   -- PM2.5 高字节
    local pm10_low = string.byte(data, 5)  -- PM10 低字节
    local pm10_high = string.byte(data, 6)   -- PM10 高字节
    -- 计算 PM2.5 和 PM10 值
    local pm25 = (pm25_high * 256 + pm25_low) / 10
    local pm10 = (pm10_high * 256 + pm10_low) / 10

    -- 检查有效性
    if pm25 >= 1 and pm25 ~= 2570 then    -- 此判断条件可根据实际情况调整
      return pm25, pm10
    else
      log.warn("i2c", "Invalid data received on channel " .. channel)
      return nil, nil
    end
  end


  -- 循环读取并输出数据
  while true do
    -- 读取通道 A 数据
    local dataA = read_T_data("A")
    local ug, max, ppb, temp, Rh = process_data_temp(dataA, "A")

    -- 读取通道 B 数据
    local dataB = read_data("B")
    local pm25B, pm10B = process_data(dataB, "B")

    -- 显示 温度 和 湿度 数据（通道 A）
    if ug then
      log.info("i2c"..I2C_ID.."--uartA", "气体浓度µg = " .. string.format("%.2f", ug) .. "µg/m³, 满量程 = " .. string.format("%.2f", max) ..", 气体浓度ppb = " .. string.format("%.2f", ppb) .."ppb, 温度 = " .. string.format("%.2f", temp) .." °C, 湿度 = " .. string.format("%.2f", Rh) .. " % "..dataA:toHex())--
    end

    -- 显示 PM2.5 和 PM10 数据（通道 B）
    if pm25B then
      log.info("i2c"..I2C_ID.."--uartB", "PM2.5 = " .. string.format("%.2f", pm25B) .. " µg/m³, PM10 = " .. string.format("%.2f", pm10B) .. " µg/m³"..dataB:toHex())
    end

    -- 延时后继续读取
    sys.wait(700)
  end
end)

sys.run()



