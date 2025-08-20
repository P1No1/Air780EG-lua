-- Luatools需要PROJECT和VERSION这两个信息
PROJECT = "uart"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")

if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

log.info("main", "uart demo run......")

local uartid = 1 -- 根据实际设备选取不同的uartid

--初始化
uart.setup(
    uartid,--串口id
    9600,--波特率
    8,--数据位
    1--停止位
)

-- 收取数据会触发回调, 这里的"receive" 是固定值
uart.on(uartid, "receive", function(id, len)
    local s = ""
    repeat  
        s = uart.read(id, 128)
        if #s > 0 then -- #s 是取字符串的长度
            -- 关于收发hex值,请查阅 https://doc.openluat.com/article/583
            
            local b1, b2, b3, b4 = string.byte(s, 1, 4)

            -- 转成数值（注意字节序，这里假设大端，也就是高字节在前）
            local num1 = (b1 << 8) | b2   -- 0x0AD8 = 2776
            local num2 = (b3 << 8) | b4   -- 0x0000 = 0

            -- log.info("uart", "温度=" .. string.format("%.2f",num1/100).."°C", "湿度=" .. string.format("%.1f",num2/100).."%")

            -- local hexstr = s:toHex()  -- "0AD80000"
            -- local part1 = hexstr:sub(1, 4)   -- "0AD8"
            log.info("uart", "receive", id, #s, s:toHex()) --如果传输二进制/十六进制数据, 部分字符不可见, 不代表没收到
        
        end 
    until s == ""
end)

sys.taskInit(function()
    -- 循环两秒向串口发一次数据
    local cmd_active_upload_1 = string.char(0xFF, 0x01, 0x78, 0x40, 0x00, 0x00, 0x00, 0x00, 0x47)
    uart.write(uartid, cmd_active_upload_1)
    while true do
        sys.wait(2000)
        
        local cmd_active_upload_2 = string.char(0xD2) --读取温度湿度
        -- uart.write(uartid, cmd_active_upload_2)
        
    end
end)

-- 用户代码已结束---------------------------------------------
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!