#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from Ov7670Cam import Ov7670Cam
import time
import matplotlib.pyplot as plt

def main():
    """示例：使用OV7670摄像头类捕获和显示图像"""
    
    print("初始化OV7670摄像头...")
    # 创建摄像头实例，使用默认参数
    camera = Ov7670Cam(
        bitstream_path="runs/camera_design.bit",
        sccb_base=0x40001000,
        camera_ctrl_base=0x40000000,
        vdma_base=0x43000000
    )
    
    # 初始化摄像头硬件
    camera.init_camera()
    print("摄像头硬件初始化完成")
    
    # 配置摄像头 - 可选择"normal"或"test_pattern"
    print("配置摄像头寄存器...")
    camera.configure_camera("normal")
    
    # 读取产品ID进行验证
    product_id = camera.read_product_id()
    print(f"OV7670产品ID: 0x{product_id:02X} (预期值: 0x76)")
    
    # 设置VDMA
    print("设置VDMA...")
    camera.setup_vdma()
    
    # 等待系统稳定
    print("等待系统稳定...")
    time.sleep(0.5)
    
    # 捕获并显示一帧
    print("捕获图像...")
    frame = camera.display_frame(title="OV7670测试图像")
    
    # 示例：读写寄存器
    print("\n寄存器读写测试:")
    test_reg = 0x3A  # 示例寄存器
    old_value = camera.read_register(test_reg)
    print(f"寄存器0x{test_reg:02X}原始值: 0x{old_value:02X}")
    
    # 修改寄存器值
    new_value = 0x04
    camera.write_register(test_reg, new_value)
    
    # 读回确认
    read_back = camera.read_register(test_reg)
    print(f"写入值: 0x{new_value:02X}, 读回值: 0x{read_back:02X}")
    print(f"测试结果: {'成功' if new_value == read_back else '失败'}")
    
    # 测试彩条模式
    print("\n切换到彩条测试模式...")
    camera.configure_camera("test_pattern")
    time.sleep(0.5)
    
    # 再次捕获显示
    print("捕获彩条测试图像...")
    camera.display_frame(title="OV7670彩条测试图像")
    
    # 清理资源
    print("\n关闭摄像头...")
    camera.close()
    print("示例运行完成")

if __name__ == "__main__":
    main() 