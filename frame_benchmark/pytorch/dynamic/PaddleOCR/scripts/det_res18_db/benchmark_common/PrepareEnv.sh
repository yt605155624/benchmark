#!/usr/bin/env bash
# 执行路径在模型库的根目录下
################################# 安装框架 如:
wget https://download.pytorch.org/whl/cu102/torch-1.7.1-cp37-cp37m-linux_x86_64.whl
python -m pip install torch-1.7.1-cp37-cp37m-linux_x86_64.whl
python -m pip install torchvision==0.8.2 torchaudio==0.7.2 -f https://download.pytorch.org/whl/torch_stable.html
python -m pip install -r requirement.txt -i https://pypi.tuna.tsinghua.edu.cn/simple
# 下载数据集并解压
rm -rf datasets
wget https://paddleocr.bj.bcebos.com/dygraph_v2.0/test/benchmark_train/datasets.tar
tar xf datasets.tar

export MASTER_ADDR="localhost"
export MASTER_PORT="6006"