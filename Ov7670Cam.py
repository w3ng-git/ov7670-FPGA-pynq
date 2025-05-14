#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from pynq import Overlay, DefaultIP, MMIO, allocate
import time
import numpy as np
import matplotlib.pyplot as plt
from typing import Tuple, List, Union, Optional

class SCCBDriver:
    """
    SCCB Driver Class for controlling SCCB controller via AXI interface.
    """
    
    # Register offset definitions (matching hardware design)
    CTRL_REG_OFFSET = 0x00       # Control register
    STATUS_REG_OFFSET = 0x04     # Status register
    TX_DATA_REG_OFFSET = 0x08    # TX data register
    RX_DATA_REG_OFFSET = 0x0C    # RX data register
    ADDR_REG_OFFSET = 0x10       # Device address register
    REG_ADDR_OFFSET = 0x14       # Slave register address offset
    
    # Control register bit definitions
    CTRL_START_BIT = 0           # Write operation start bit
    CTRL_READ_BIT = 1            # Read operation start bit
    CTRL_STOP_BIT = 2            # Stop bit
    CTRL_ACK_BIT = 3             # ACK control bit
    CTRL_IRQ_EN_BIT = 4          # Interrupt enable bit
    
    # Status register bit definitions
    STAT_BUSY_BIT = 0            # Busy status bit
    STAT_ACK_ERR_BIT = 2         # ACK error bit
    STAT_ARB_LOST_BIT = 3        # Arbitration lost bit
    
    def __init__(self, description, base_address=0x40001000):
        """
        Initialize SCCB driver.
        
        Args:
            description: IP core description (required by PYNQ) or custom description string
            base_address: AXI base address
        """
        # Check if description is dictionary or string
        if isinstance(description, dict):
            # If dictionary, it's automatically bound by DefaultIP
            super().__init__(description=description)
        else:
            # If string, create manually
            self.description = description
            self.mmio = MMIO(base_address, 0x1000)
            
        self.base_address = base_address
        
    def write_register(self, offset, value):
        """Write to AXI register"""
        if hasattr(self, 'write'):
            self.write(offset, value)
        else:
            self.mmio.write(offset, value)
        
    def read_register(self, offset):
        """Read from AXI register"""
        if hasattr(self, 'read'):
            return self.read(offset)
        else:
            return self.mmio.read(offset)
    
    def wait_for_done(self, timeout=0.2):
        """Wait for transfer completion"""
        start_time = time.time()
        while (time.time() - start_time) < timeout:
            status = self.read_register(self.STATUS_REG_OFFSET)
            if status & (1 << self.STAT_BUSY_BIT):
                return True
            time.sleep(0.001)
        return False
    
    def wait_for_not_busy(self, timeout=0.1):
        """Wait for not busy status"""
        start_time = time.time()
        while (time.time() - start_time) < timeout:
            status = self.read_register(self.STATUS_REG_OFFSET)
            if not (status & (1 << self.STAT_BUSY_BIT)):
                return True
            time.sleep(0.001)
        return False
    
    def set_device_address(self, device_addr):
        """Set SCCB device address"""
        self.write_register(self.ADDR_REG_OFFSET, device_addr & 0x7F)
    
    def set_register_address(self, reg_addr):
        """Set slave register address"""
        self.write_register(self.REG_ADDR_OFFSET, reg_addr & 0xFF)
    
    def write_byte(self, device_addr, reg_addr, data):
        """Write a byte to SCCB device"""
        self.set_device_address(device_addr)
        self.set_register_address(reg_addr)
        self.write_register(self.TX_DATA_REG_OFFSET, data & 0xFF)
        ctrl_value = (1 << self.CTRL_START_BIT) | (1 << self.CTRL_STOP_BIT)
        self.write_register(self.CTRL_REG_OFFSET, ctrl_value)
        return self.wait_for_done()
    
    def read_byte(self, device_addr, reg_addr):
        """Read a byte from SCCB device"""
        self.set_device_address(device_addr)
        self.set_register_address(reg_addr)
        ctrl_value = (1 << self.CTRL_READ_BIT) | (1 << self.CTRL_STOP_BIT)
        self.write_register(self.CTRL_REG_OFFSET, ctrl_value)
        time.sleep(0.01)
        data = self.read_register(self.RX_DATA_REG_OFFSET)
        return data & 0xFF
    
    def write_data(self, device_addr, reg_addr, data_bytes):
        """Write multiple bytes to SCCB device"""
        for i, data_byte in enumerate(data_bytes):
            if not self.write_byte(device_addr, reg_addr + i, data_byte):
                return False
            time.sleep(0.01)
        return True
    
    def read_data(self, device_addr, reg_addr, length):
        """Read multiple bytes from SCCB device"""
        result = []
        for i in range(length):
            data = self.read_byte(device_addr, reg_addr + i)
            if data is None:
                return []
            result.append(data)
            time.sleep(0.001)
        return result

class Ov7670Cam:
    """OV7670摄像头驱动类，整合SCCB、摄像头控制和VDMA功能"""
    
    # OV7670 SCCB地址
    OV7670_ADDR = 0x21
    
    # 预设配置
    CONFIG_NORMAL = [
        # ---------- 软复位 ----------
        (0x12, 0x80), ("delay", 10),

        # ---------- 输出格式 RGB565 ----------
        (0x12, 0x04),
        (0x3A, 0x04),
        (0x40, 0xD0),

        # ---------- VGA 640x480 ----------
        (0x17, 0x16), (0x18, 0x04),
        (0x19, 0x02), (0x1A, 0x7B),
        (0x03, 0x06), (0x32, 0x80),

        # ---------- 同步极性 / 镜像 ----------
        (0x15, 0x00),
        (0x1E, 0x07),

        # ---------- 色彩矩阵：正常 RGB 恢复 ----------
        (0x4F, 0xB3),  # R 主
        (0x50, 0xB3),  # R 副
        (0x51, 0x00),  # 交叉项
        (0x52, 0x3D),  # G 主
        (0x53, 0xA7),  # G 副
        (0x54, 0xE4),  # B 主
        (0x58, 0x9E),  # 矩阵符号控制

        # ---------- 增益限制 + 自动控制 ----------
        (0x14, 0x6A),
        (0x13, 0xE7),
        (0x3D, 0xC2),
    ]
    
    CONFIG_TEST_PATTERN = [
        (0x12, 0x80),         # 软件复位
        ("delay", 10),

        (0x11, 0x01),         # 时钟分频
        (0x6B, 0x00),         # PLL off

        (0x12, 0x04),         # RGB输出模式
        (0x40, 0xD0),         # RGB565 + full range

        (0x3A, 0x04),         # 正常输出顺序
        (0x70, 0x80),         # 开启彩条测试
        (0x71, 0x81),
    ]
    
    def __init__(self, bitstream_path="runs/camera_design.bit",
                 sccb_base=0x40001000, camera_ctrl_base=0x40000000,
                 vdma_base=0x43000000, width=640, height=480):
        """
        初始化OV7670摄像头
        
        参数:
            bitstream_path: 比特流文件路径
            sccb_base: SCCB控制器基地址
            camera_ctrl_base: 摄像头控制器基地址
            vdma_base: VDMA基地址
            width: 图像宽度
            height: 图像高度
        """
        self.width = width
        self.height = height
        self.bytes_per_pixel = 4  # RGBA8888
        
        # 加载比特流
        self.overlay = Overlay(bitstream_path)
        
        # 初始化SCCB驱动
        self.sccb = SCCBDriver("SCCB Controller", base_address=sccb_base)
        
        # 初始化摄像头控制寄存器
        self.camera_mmio = MMIO(camera_ctrl_base, 0x1000)
        
        # VDMA和帧缓冲区
        self.vdma = None
        self.frame_buffer = None
        
        # 摄像头参数
        self.initialized = False
    
    def init_camera(self):
        """初始化摄像头硬件"""
        # Step 1：确保处于掉电状态
        self.camera_mmio.write(0x00, 0x00)    # 禁用 + 掉电
        time.sleep(0.02)                       # 等待 ≥5ms

        # Step 2：开启摄像头（正常工作模式）
        self.camera_mmio.write(0x00, 0x01)    # 使能 + 电源模式 00
        time.sleep(0.05)                       # 等待 ≥10ms 模拟前端稳定
        
        self.initialized = True
        return True
    
    def configure_camera(self, config_type="normal"):
        """配置摄像头寄存器"""
        if not self.initialized:
            self.init_camera()
            
        # 选择配置类型
        if config_type.lower() == "test_pattern":
            config = self.CONFIG_TEST_PATTERN
        else:
            config = self.CONFIG_NORMAL
            
        # 应用配置
        for reg, val in config:
            if reg == "delay":
                time.sleep(val / 1000)  # 毫秒延时
            else:
                self.sccb.write_byte(self.OV7670_ADDR, reg, val)
                time.sleep(0.003)       # 写后留3ms，保险
        
        return True
    
    def setup_vdma(self, circular=True, frame_count=1):
        """配置VDMA用于图像帧捕获"""
        vdma = MMIO(0x43000000, 0x10000)
        fb = allocate(shape=(self.height, self.width), dtype="uint32")  # 32-bit RGBA

        stride = self.width * self.bytes_per_pixel
        phys_addr = fb.physical_address

        # 1. Reset S2MM
        vdma.write(0x30, 0x00000004)       # S2MM_DMACR soft reset
        while vdma.read(0x34) & 0x00000004:
            pass                           # wait reset complete
        vdma.write(0x30, 0x00000001)
        
        # 2. Set Frame Buffer Start Address
        vdma.write(0xAC, phys_addr)        # S2MM_START_ADDR

        # 3. Set Stride, HSIZE, VSIZE (S2MM)
        vdma.write(0xA8, stride)           # S2MM_FRMDLY_STRIDE
        vdma.write(0xA4, stride)           # S2MM_HSIZE in bytes
        vdma.write(0xA0, self.height)      # S2MM_VSIZE in lines

        # 4. Start VDMA
        dmacr = 0x1                        # RS=1, start DMA
        if circular:
            dmacr |= (1 << 16)             # Circular mode
        if frame_count == 3:
            dmacr |= (3 << 17)             # Frame delay
        vdma.write(0x30, dmacr)

        time.sleep(0.001)                  # 给点时间稳定

        self.vdma = vdma
        self.frame_buffer = fb
        return fb, vdma
    
    def capture_frame(self):
        """捕获一帧图像"""
        if self.frame_buffer is None:
            self.setup_vdma()
            time.sleep(0.1)  # 等待首帧捕获
            
        # 缓存同步
        if hasattr(self.frame_buffer, "invalidate_cache"):
            self.frame_buffer.invalidate_cache()
        elif hasattr(self.frame_buffer, "invalidate"):
            self.frame_buffer.invalidate()
        else:
            self.frame_buffer.sync_from_device()
        
        # 转换视图
        rgba = self.frame_buffer.view(dtype=np.uint8).reshape((self.height, self.width, 4))
        # 返回RGB格式，因为Video DMA是小端序，调整通道顺序
        return rgba[..., [3, 2, 1]] # VDMA in mem: ABGR (hardware issue), so we use the last three channels
    
    def display_frame(self, title="OV7670 Camera Frame"):
        """捕获并显示一帧图像"""
        frame = self.capture_frame()
        plt.figure(figsize=(10, 8))
        plt.imshow(frame)
        plt.title(title)
        plt.axis('off')
        plt.show()
        return frame
    
    def read_product_id(self):
        """读取OV7670的产品ID"""
        product_id = self.sccb.read_byte(self.OV7670_ADDR, 0x0A)
        return product_id
    
    def write_register(self, reg_addr, value):
        """写入摄像头寄存器"""
        return self.sccb.write_byte(self.OV7670_ADDR, reg_addr, value)
        
    def read_register(self, reg_addr):
        """读取摄像头寄存器"""
        return self.sccb.read_byte(self.OV7670_ADDR, reg_addr)
    
    def close(self):
        """关闭摄像头"""
        # 掉电
        self.camera_mmio.write(0x00, 0x00)
        self.initialized = False
        
        # 释放资源
        if self.frame_buffer is not None:
            self.frame_buffer.close()
            self.frame_buffer = None 