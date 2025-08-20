PROJECT = "sc16is752_demo"
VERSION = "1.0.0"
sys = require("sys")

local i2cid = 1
local addr = 0x4D   -- SC16IS752 的 7bit 地址（取决于 A0/A1 脚）

-- 子地址计算：reg(0~15)，ch="A"/"B"
local function subaddr(reg, ch)
    local chbits = (ch=="B") and 1 or 0
    return (reg & 0x0F) << 3 | (chbits << 1)
end

sys.taskInit(function()
    log.info("i2c", "setup", i2c.setup(i2cid))

    -- ===== 写操作示例：往 THR 寄存器（0x00）写入 8 字节 =====
    local tx_data = "1234abcd"
    i2c.send(i2cid, addr, string.char(subaddr(0x00,"A")) .. tx_data)
    sys.wait(100)

    -- ===== 读操作示例：从 RHR 寄存器（0x00）读取 8 字节 =====
    i2c.send(i2cid, addr, string.char(subaddr(0x00,"A")))
    local rx = i2c.recv(i2cid, addr, 8)
    log.info("i2c", "rx", rx:toHex(), rx)

    while true do
        sys.wait(1000)
    end
end)

sys.run()
