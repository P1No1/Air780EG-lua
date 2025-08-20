# SC16IS752.py 从 C++ 版本 SC16IS752_rsk.cpp 移植到 ESP32 Micropython  
# 用于在 ESP32 上通过 I2C 接口驱动 SC16IS752 芯片（串口扩展 + GPIO 扩展器）的库  
# 最初由 rsk 创建，从 liamaha/SC16IS752_ESP8266 移植  
# 由 agronaut 移植到 Micro Python  

from machine import Pin, I2C

# 通道定义
SC16IS752_CHANNEL_A = const(0x00)
SC16IS752_CHANNEL_B = const(0x01)

# UART（串口）寄存器
SC16IS752_RHR = const(0x00) # 接收保持寄存器（在“读模式”下地址为 0x00）
SC16IS752_THR = const(0x00) # 发送保持寄存器（在“写模式”下地址为 0x00）

# GPIO 控制寄存器
SC16IS752_IODir = const(0x0A)    # GPIO 方向寄存器（控制输入/输出方向）
SC16IS752_IOState = const(0x0B)  # GPIO 状态寄存器（读取引脚电平状态）
SC16IS752_IOIntEna = const(0x0C) # GPIO 中断使能寄存器
SC16IS752_IOControl = const(0x0E) # GPIO 控制寄存器

SC16IS752_IER = const(0x01)  # 中断使能寄存器

SC16IS752_FCR = const(0x02)  # FIFO 控制寄存器（写模式下）
SC16IS752_IIR = const(0x02)  # 中断识别寄存器（读模式下）

SC16IS752_LCR = const(0x03)  # 线路控制寄存器（设置数据位、停止位、校验位等）
SC16IS752_MCR = const(0x04)  # 调制解调器控制寄存器
SC16IS752_LSR = const(0x05)  # 线路状态寄存器
SC16IS752_MSR = const(0x06)  # 调制解调器状态寄存器
SC16IS752_SPR = const(0x07)  # ScratchPad（临时存储）寄存器
SC16IS752_TCR = const(0x06)  # 传输控制寄存器
SC16IS752_TLR = const(0x07)  # 触发电平寄存器
SC16IS752_TXLVL = const(0x08)  # 发送 FIFO 可用空间寄存器
SC16IS752_RXLVL = const(0x09)  # 接收 FIFO 已接收数据寄存器
SC16IS752_EFCR = const(0x0F)  # 扩展功能控制寄存器

# 波特率分频寄存器
SC16IS752_DLL = const(0x00)  # 分频寄存器低字节（Divisor Latch LSB）
SC16IS752_DLH = const(0x01)  # 分频寄存器高字节（Divisor Latch MSB）

SC16IS752_EFR = const(0x02)  # 增强功能寄存器


"""
波特率与分频系数对照表
    波特率    分频值
    2400    48
    3600    32
    4800    24
    7200    16
    9600    12
    19200   6
"""

class SC16IS752():
    def __init__(self, i2c, address, channel):
        self._outputRegVal = 0x00
        self._inputRegVal = 0x00
        self._deviceAddress = address
        self._channel = channel
        self._i2c = i2c


    ## -------------------- 私有函数 -----------------------

    def _readRegister(self, regAddress):
        # 注意这里的 << 3 左移，这是“未在文档中说明”的细节，
        # 实际寄存器地址需要在手册列出的基础上再移位。
        # 通道选择也是同样的原理。
        result = self._i2c.readfrom_mem(self._deviceAddress, regAddress << 3 | self._channel << 1, 1)
        #print('读取寄存器', regAddress, '结果: ', result)
        return result
    

    def _writeRegister(self, regAddress, data):
        if isinstance(data, bytes):
            r = data
        else:
            r = bytes([data])
        
        self._i2c.writeto_mem(self._deviceAddress, regAddress << 3 | self._channel << 1, r)
        #print('写寄存器: ', regAddress << 3 | self._channel << 1, '数据: ', r)


    def _uartConnected(self):
        TEST_CHARACTER = 0x88    
        self._writeRegister(SC16IS752_SPR, TEST_CHARACTER)
        return (self._readRegister(SC16IS752_SPR) == bytes([TEST_CHARACTER]))

    
    def _bitwise_and_bytes(self, a, b):
        result_int = int.from_bytes(a, "big") & int.from_bytes(b, "big")
        return result_int.to_bytes(max(len(a), len(b)), "big")
    
    
    def _bitwise_or_bytes(self, a, b):
        result_int = int.from_bytes(a, "big") | int.from_bytes(b, "big")
        return result_int.to_bytes(max(len(a), len(b)), "big") 


    # -------------------- 公有函数 ---------------------------

    def available(self):
        # 获取接收缓冲区（64字节容量）中可读取的字节数。
        # 也就是已经到达并存放在接收缓存的数据量。
  
        # 另一种方法：只判断是否有数据（不返回数量）：
        # print('LSR 寄存器: ', self._readRegister(SC16IS752_LSR))
        # print('接收缓冲区中存放的数据', self._bitwise_and_bytes(self._readRegister(SC16IS752_LSR), b'\x01'))
        
        return int.from_bytes(self._readRegister(SC16IS752_RXLVL), 'big')


    def txBufferSize(self):
	    # 返回发送缓冲区剩余空间数量（字节数）。如果是 0，说明发送缓冲区已满。
        print('发送缓冲区大小: ', self._readRegister(SC16IS752_TXLVL))
        return self._readRegister(SC16IS752_TXLVL)


    def read_byte(self):
        return self._readRegister(SC16IS752_RHR)

    
    # 读取整个接收缓冲区的数据（即一段完整的字节序列）
    # 如果超过 64 字节，剩余的数据会排队等待，可以通过后续 read_buf 调用继续读取。
    def read_buf(self, buf_size=100):
        buf = bytearray(buf_size)
        # 这里的延时是通过实验确定的。
        # 如果延时不足，会导致读取缓冲区最后部分时出错。
        # 当用 polling available() 方式触发读取时需要延时；
        # 如果是用中断触发读取，则应去掉这个延时。
        # utime.sleep_ms(20)
        self._i2c.readfrom_mem_into(self._deviceAddress, SC16IS752_RHR << 3 | self._channel << 1, buf)
        return buf


    def write(self, value):
	    # 写入一个字节到 UART。
	
        while(self._readRegister(SC16IS752_TXLVL) == 0):
            # 等待发送缓冲区有空位。返回值表示缓冲区剩余空间。
            pass
        self._writeRegister(SC16IS752_THR, value); 


    #  ----------------------------------- rsk 添加的函数 -------

    def flush(self):
        print('[INFO]: 清空缓冲区...')
        while self.available() > 0:
            self.read_byte()


    def SetBaudrate(self, baudrateDivisor):
        # 根据数据手册第17页的“波特率分频”方式来设置波特率
        print('[INFO]: 设置波特率...')
        temp_lcr = self._readRegister(SC16IS752_LCR)
        temp_lcr = self._bitwise_or_bytes(bytes(temp_lcr), b'\x80')  # 设置DLAB位以允许访问 DLL/DLH

        self._writeRegister(SC16IS752_LCR, temp_lcr[0])
        # 写入 DLL（低字节）
        self._writeRegister(SC16IS752_DLL, baudrateDivisor)
        # 写入 DLH（高字节）
        self._writeRegister(SC16IS752_DLH, baudrateDivisor>>8)

        temp_lcr= self._bitwise_and_bytes(bytes(temp_lcr), b'\x7F')  # 清除 DLAB 位
        self._writeRegister(SC16IS752_LCR, temp_lcr[0])


    # 这个函数“理论上”用来复位，但在实际测试中不起作用。
    # 比如写入 b'\x08' 到 SC16IS752_IOControl 时，值似乎过大，导致无效。
    def ResetDevice(self):
        reg = self._readRegister(SC16IS752_IOControl)
        reg = self._bitwise_or_bytes(bytes(reg), b'\x08')
        # print('寄存器: ', reg)
        self._writeRegister(SC16IS752_IOControl, reg[0])


    def FIFOEnable(self, fifo_enable):
        print('[INFO]: 启用 FIFO...')
        temp_fcr = self._readRegister(SC16IS752_FCR)

        if fifo_enable == 0:
            temp_fcr = self._bitwise_and_bytes(bytes(temp_fcr), b'\xFE')  # 清除使能位
        else:
            temp_fcr = self._bitwise_or_bytes(bytes(temp_fcr), b'\x01')   # 设置使能位
        
        self._writeRegister(SC16IS752_FCR, temp_fcr[0])


    def SetLine(self, data_length, parity_select, stop_length):
        print('[INFO]: 配置串口线路参数...')
        temp_lcr = self._readRegister(SC16IS752_LCR)
        temp_lcr = self._bitwise_and_bytes(bytes(temp_lcr), b'\xC0') # 清除 LCR 低 6 位（数据位/校验位/停止位配置区）

        # 数据位设置
        if data_length == 5:          
            pass
        elif data_length == 6:
            temp_lcr = self._bitwise_or_bytes(bytes(temp_lcr), b'\x01')
        elif data_length == 7:
            temp_lcr = self._bitwise_or_bytes(bytes(temp_lcr), b'\x02')
        elif data_length == 8:
            temp_lcr = self._bitwise_or_bytes(bytes(temp_lcr), b'\x03')
        else:
            temp_lcr = self._bitwise_or_bytes(bytes(temp_lcr), b'\x03')  # 默认 8 位


        # 停止位设置
        if ( stop_length == 2 ):
            temp_lcr = self._bitwise_or_bytes(bytes(temp_lcr), b'\x04')

        # 校验位设置
        if parity_select == 0:           # 无校验
            pass
        elif parity_select == 1:         # 奇校验
            temp_lcr = self._bitwise_or_bytes(bytes(temp_lcr), b'\x08')
        elif parity_select == 2:         # 偶校验
            temp_lcr = self._bitwise_or_bytes(bytes(temp_lcr), b'\x18')
        elif parity_select == 3:         # 保留/不常用
            temp_lcr = self._bitwise_or_bytes(bytes(temp_lcr), b'\x03')
        elif parity_select == 4:         # 强制校验位为 1/0（很少用）
            pass

        self._writeRegister(SC16IS752_LCR, temp_lcr[0])
        
        # 启用中断：只有当 RHR（接收保持寄存器）中有数据时才触发 IRQ 引脚。
        # 可查阅手册“Receive Holding Register interrupt” 对应 IER[0] 位。
        self._writeRegister(SC16IS752_IER, b'\x01')
