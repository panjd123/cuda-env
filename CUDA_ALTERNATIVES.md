# CUDA Switching With `update-alternatives`

这份文档说明如何在容器里直接使用 `update-alternatives` 管理多个 CUDA Toolkit 版本，而不依赖额外包装脚本。

适用前提：

- 机器上已经同时安装了多个 CUDA 目录，例如：
  - `/usr/local/cuda-12.8`
  - `/usr/local/cuda-13.0`
  - `/usr/local/cuda-13.2`
- 你希望统一通过 `/usr/local/cuda` 作为默认入口

## 1. 注册多个 CUDA 版本

如果还没注册过，可以执行：

```bash
sudo update-alternatives --install /usr/local/cuda cuda /usr/local/cuda-12.8 120800
sudo update-alternatives --install /usr/local/cuda cuda /usr/local/cuda-13.0 130000
sudo update-alternatives --install /usr/local/cuda cuda /usr/local/cuda-13.2 130200
```

这里：

- `/usr/local/cuda` 是统一入口
- `cuda` 是 alternatives 组名
- 最后的数字是 priority，通常版本越高优先级越高

## 2. 查看当前状态

查看 alternatives 状态：

```bash
update-alternatives --display cuda
```

或：

```bash
update-alternatives --query cuda
```

查看 `/usr/local/cuda` 当前实际指向：

```bash
readlink -f /usr/local/cuda
```

查看编译器版本：

```bash
/usr/local/cuda/bin/nvcc --version
```

## 3. 切换默认 CUDA 版本

切到 `12.8`：

```bash
sudo update-alternatives --set cuda /usr/local/cuda-12.8
```

切到 `13.0`：

```bash
sudo update-alternatives --set cuda /usr/local/cuda-13.0
```

切到 `13.2`：

```bash
sudo update-alternatives --set cuda /usr/local/cuda-13.2
```

切换后再确认：

```bash
readlink -f /usr/local/cuda
/usr/local/cuda/bin/nvcc --version
```

## 4. 恢复自动选择最高优先级版本

如果你不想手动固定某个版本，可以恢复 auto mode：

```bash
sudo update-alternatives --auto cuda
```

这时会自动选 priority 最高的那个 CUDA 目录。

## 5. 让当前 shell 立即跟上

`update-alternatives` 改的是 `/usr/local/cuda` 这个 symlink。

如果你的环境变量本来就是：

```bash
export CUDA_HOME=/usr/local/cuda
export PATH=/usr/local/cuda/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:/usr/local/cuda/extras/CUPTI/lib64:$LD_LIBRARY_PATH
```

那么新开的 shell 会自然跟随切换结果。

如果你已经在当前 shell 里工作，建议执行一次：

```bash
export CUDA_HOME=/usr/local/cuda
export PATH=/usr/local/cuda/bin:${PATH//\/usr\/local\/cuda[^:]*\/bin:/}
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:/usr/local/cuda/extras/CUPTI/lib64:${LD_LIBRARY_PATH}
hash -r
```

更简单的做法是：切换后直接开一个新的 shell。

## 6. 推荐的 `.bashrc` 写法

如果你希望永远跟随 `/usr/local/cuda`，推荐在 `~/.bashrc` 里只写这一套：

```bash
export CUDA_HOME=/usr/local/cuda
export PATH=/usr/local/cuda/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:/usr/local/cuda/extras/CUPTI/lib64:$LD_LIBRARY_PATH
```

不要把 `12.8`、`13.0`、`13.2` 这种具体版本硬编码进 `.bashrc`。

## 7. 新增一个 CUDA 版本时怎么做

假设以后又装了 `/usr/local/cuda-13.3`，只要再注册一次：

```bash
sudo update-alternatives --install /usr/local/cuda cuda /usr/local/cuda-13.3 130300
```

然后就可以：

```bash
sudo update-alternatives --set cuda /usr/local/cuda-13.3
```

## 8. 适合这个容器的最小工作流

日常其实只需要记住这几条：

```bash
update-alternatives --display cuda
sudo update-alternatives --set cuda /usr/local/cuda-12.8
sudo update-alternatives --set cuda /usr/local/cuda-13.0
sudo update-alternatives --set cuda /usr/local/cuda-13.2
readlink -f /usr/local/cuda
nvcc --version
```

当前这个容器就是按这个最小方案实现的：

- `update-alternatives --install ...`
- `.bashrc` 里统一指向 `/usr/local/cuda`

对个人开发容器，这通常已经够用了。
