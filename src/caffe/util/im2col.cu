#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstring>

#include "caffe/common.hpp"
#include "caffe/util/im2col.hpp"

namespace caffe {

template <typename Dtype>
__global__ void im2col_sk_gpu_kernel(const int n, const Dtype* data_im,
    const int height, const int width, const int kernel_h, const int kernel_w,
    const int ext_kernel_h, const int ext_kernel_w,
    const int pad_h, const int pad_w,
    const int stride_h, const int stride_w,
    const int kstride_h, const int kstride_w,
    const int height_col, const int width_col,
    Dtype* data_col) {
  CUDA_KERNEL_LOOP(index, n) {
    int w_out = index % width_col;
    int h_index = index / width_col;
    int h_out = h_index % height_col;
    int channel_in = h_index / height_col;
    int channel_out = channel_in * kernel_h * kernel_w;
    int h_in = h_out * stride_h - pad_h;
    int w_in = w_out * stride_w - pad_w;
    Dtype* data_col_ptr = data_col;
    data_col_ptr += (channel_out * height_col + h_out) * width_col + w_out;
    const Dtype* data_im_ptr = data_im;
    data_im_ptr += (channel_in * height + h_in) * width + w_in;
    for (int i = 0; i < ext_kernel_h; i += kstride_h) {
      for (int j = 0; j < ext_kernel_w; j += kstride_w) {
        int h = h_in + i;
        int w = w_in + j;
        *data_col_ptr = (h >= 0 && w >= 0 && h < height && w < width) ?
            data_im_ptr[i * width + j] : 0;
        data_col_ptr += height_col * width_col;
      }
    }
  }
}


template <typename Dtype>
void im2col_sk_gpu(const Dtype* data_im, const int channels,
    const int height, const int width, const int kernel_h, const int kernel_w,
    const int pad_h, const int pad_w,
    const int stride_h, const int stride_w,
    const int kstride_h, const int kstride_w,
    Dtype* data_col) {
  // We are going to launch channels * height_col * width_col kernels, each
  // kernel responsible for copying a single-channel grid.
  int ext_kernel_h = (kernel_h - 1) * kstride_h + 1;
  int ext_kernel_w = (kernel_w - 1) * kstride_w + 1;
  int height_col = (height + 2 * pad_h - ext_kernel_h) / stride_h + 1;
  int width_col = (width + 2 * pad_w - ext_kernel_w) / stride_w + 1;
  int num_kernels = channels * height_col * width_col;

  //LOG(INFO) << "ext_height = " << ext_kernel_h;
  //LOG(INFO) << "ext_width = " << ext_kernel_w;

  // NOLINT_NEXT_LINE(whitespace/operators)
  im2col_sk_gpu_kernel<Dtype><<<CAFFE_GET_BLOCKS(num_kernels),
                             CAFFE_CUDA_NUM_THREADS>>>(
      num_kernels, data_im, height, width, kernel_h, kernel_w,
      ext_kernel_h, ext_kernel_w, pad_h, pad_w, stride_h, stride_w, kstride_h, kstride_w,
      height_col, width_col,
      data_col);
  CUDA_POST_KERNEL_CHECK;
}

// Explicit instantiation
template void im2col_sk_gpu<float>(const float* data_im, const int channels,
    const int height, const int width, const int kernel_h, const int kernel_w,
    const int pad_h, const int pad_w, const int stride_h, const int stride_w,
    const int kstride_h, const int kstride_w,
    float* data_col);
template void im2col_sk_gpu<double>(const double* data_im, const int channels,
    const int height, const int width, const int kernel_h, const int kernel_w,
    const int pad_h, const int pad_w, const int stride_h, const int stride_w,
    const int kstride_h, const int kstride_w,
    double* data_col);

template <typename Dtype>
__global__ void col2im_sk_gpu_kernel(const int n, const Dtype* data_col,
    const int height, const int width, const int channels,
    const int patch_h, const int patch_w,
    const int ext_patch_h, const int ext_patch_w,
    const int pad_h, const int pad_w,
    const int stride_h, const int stride_w,
    const int kstride_h, const int kstride_w,
    const int height_col, const int width_col,
    Dtype* data_im) {
  CUDA_KERNEL_LOOP(index, n) {
    Dtype val = 0;
    int w = index % width + pad_w;
    int h = (index / width) % height + pad_h;
    int c = index / (width * height);
    // compute the start and end of the output
    int width_col_1 = width_col - 1;
    int height_col_1 = height_col - 1;
    int w_col_start = (w < ext_patch_w) ? w % kstride_w : (w - ext_patch_w)+ 1;
    int w_col_end = (w >= width_col) ?  width_col_1 - (width_col_1 - w_col_start) % kstride_w : w;
    int h_col_start = (h < ext_patch_h) ? h % kstride_h : (h - ext_patch_h) + 1;
    int h_col_end = (h >= height_col) ? height_col_1 - (height_col_1 - h_col_start) % kstride_h : h;
    int w_num = (w - w_col_start) / kstride_w;
    int h_num = (h - h_col_start) / kstride_h;

    int coeff_w_idx = height_col * width_col;
    int coeff_h_idx = patch_w * coeff_w_idx;
    int offset = c * patch_h * coeff_h_idx;
    for (int h_col = h_col_start, h_idx = h_num; h_col <= h_col_end; h_col += kstride_h, --h_idx) {
      for (int w_col = w_col_start, w_idx = w_num; w_col <= w_col_end; w_col += kstride_w, --w_idx) {
        //int c_col = c * patch_h * patch_w + (h - h_col) / kstride_h * patch_w + (w - w_col) / kstride_w;
        //int c_col = c * patch_h * patch_w + h_idx * patch_w + w_idx;
        //val += data_col[(c_col * height_col + h_col) * width_col + w_col];
        val += data_col[offset + h_idx * coeff_h_idx + w_idx * coeff_w_idx + h_col * width_col + w_col];
      }
    }

    data_im[index] = val;
  }
}

template <typename Dtype>
void col2im_sk_gpu(const Dtype* data_col, const int channels,
    const int height, const int width, const int patch_h, const int patch_w,
    const int pad_h, const int pad_w, const int stride_h,
    const int stride_w, const int kstride_h, const int kstride_w,
    Dtype* data_im) {
  if (stride_w > 1 || stride_h > 1 || pad_h > 0 || pad_w > 0)
    LOG(FATAL) << "stride greater than 1 or pad greater than 0 not tested in col2im_sk_gpu().";
  int ext_patch_h = (patch_h - 1) * kstride_h + 1;
  int ext_patch_w = (patch_w - 1) * kstride_w + 1;
  int height_col = (height + 2 * pad_h - ext_patch_h) / stride_h + 1;
  int width_col = (width + 2 * pad_w - ext_patch_w) / stride_w + 1;
  int num_kernels = channels * height * width;

  col2im_sk_gpu_kernel<Dtype><<<CAFFE_GET_BLOCKS(num_kernels),
                             CAFFE_CUDA_NUM_THREADS>>>(
      num_kernels, data_col, height, width, channels,
      patch_h, patch_w, ext_patch_h, ext_patch_w,
      pad_h, pad_w, stride_h, stride_w, kstride_h, kstride_w,
      height_col, width_col, data_im);
  CUDA_POST_KERNEL_CHECK;
}

// Explicit instantiation
template void col2im_sk_gpu<float>(const float* data_col, const int channels,
    const int height, const int width, const int patch_h, const int patch_w,
    const int pad_h, const int pad_w, const int stride_h,
    const int stride_w, const int kstride_h, const int kstride_w, float* data_im);
template void col2im_sk_gpu<double>(const double* data_col, const int channels,
    const int height, const int width, const int patch_h, const int patch_w,
    const int pad_h, const int pad_w, const int stride_h,
    const int stride_w, const int kstride_h, const int kstride_w, double* data_im);

template <typename Dtype>
__global__ void im2col_gpu_kernel(const int n, const Dtype* data_im,
    const int height, const int width, const int kernel_h, const int kernel_w,
    const int pad_h, const int pad_w,
    const int stride_h, const int stride_w,
    const int height_col, const int width_col,
    Dtype* data_col) {
  CUDA_KERNEL_LOOP(index, n) {
    int w_out = index % width_col;
    int h_index = index / width_col;
    int h_out = h_index % height_col;
    int channel_in = h_index / height_col;
    int channel_out = channel_in * kernel_h * kernel_w;
    int h_in = h_out * stride_h - pad_h;
    int w_in = w_out * stride_w - pad_w;
    Dtype* data_col_ptr = data_col;
    data_col_ptr += (channel_out * height_col + h_out) * width_col + w_out;
    const Dtype* data_im_ptr = data_im;
    data_im_ptr += (channel_in * height + h_in) * width + w_in;
    for (int i = 0; i < kernel_h; ++i) {
      for (int j = 0; j < kernel_w; ++j) {
        int h = h_in + i;
        int w = w_in + j;
        *data_col_ptr = (h >= 0 && w >= 0 && h < height && w < width) ?
            data_im_ptr[i * width + j] : 0;
        data_col_ptr += height_col * width_col;
      }
    }
  }
}

template <typename Dtype>
void im2col_gpu(const Dtype* data_im, const int channels,
    const int height, const int width, const int kernel_h, const int kernel_w,
    const int pad_h, const int pad_w,
    const int stride_h, const int stride_w,
    Dtype* data_col) {
  // We are going to launch channels * height_col * width_col kernels, each
  // kernel responsible for copying a single-channel grid.
  int height_col = (height + 2 * pad_h - kernel_h) / stride_h + 1;
  int width_col = (width + 2 * pad_w - kernel_w) / stride_w + 1;
  int num_kernels = channels * height_col * width_col;
  // NOLINT_NEXT_LINE(whitespace/operators)
  im2col_gpu_kernel<Dtype><<<CAFFE_GET_BLOCKS(num_kernels),
                             CAFFE_CUDA_NUM_THREADS>>>(
      num_kernels, data_im, height, width, kernel_h, kernel_w, pad_h,
      pad_w, stride_h, stride_w, height_col,
      width_col, data_col);
  CUDA_POST_KERNEL_CHECK;
}


// Explicit instantiation
template void im2col_gpu<float>(const float* data_im, const int channels,
    const int height, const int width, const int kernel_h, const int kernel_w,
    const int pad_h, const int pad_w, const int stride_h, const int stride_w,
    float* data_col);
template void im2col_gpu<double>(const double* data_im, const int channels,
    const int height, const int width, const int kernel_h, const int kernel_w,
    const int pad_h, const int pad_w, const int stride_h, const int stride_w,
    double* data_col);

template <typename Dtype>
__global__ void col2im_gpu_kernel(const int n, const Dtype* data_col,
    const int height, const int width, const int channels,
    const int patch_h, const int patch_w,
    const int pad_h, const int pad_w,
    const int stride_h, const int stride_w,
    const int height_col, const int width_col,
    Dtype* data_im) {
  CUDA_KERNEL_LOOP(index, n) {
    Dtype val = 0;
    int w = index % width + pad_w;
    int h = (index / width) % height + pad_h;
    int c = index / (width * height);
    // compute the start and end of the output
    int w_col_start = (w < patch_w) ? 0 : (w - patch_w) / stride_w + 1;
    int w_col_end = min(w / stride_w + 1, width_col);
    int h_col_start = (h < patch_h) ? 0 : (h - patch_h) / stride_h + 1;
    int h_col_end = min(h / stride_h + 1, height_col);
    /*
    for (int h_col = h_col_start; h_col < h_col_end; ++h_col) {
      for (int w_col = w_col_start; w_col < w_col_end; ++w_col) {
        // the col location: [c * width * height + h_out, w_out]
        int c_col = c * patch_h * patch_w + (h - h_col * stride_h) * ksize
            + (w - w_col * stride_w);
        val += data_col[(c_col * height_col + h_col) * width_col + w_col];
      }
    }
    */
    // equivalent implementation
    int offset =
        (c * patch_h * patch_w + h * patch_w + w) * height_col * width_col;
    int coeff_h_col = (1 - stride_h * patch_w * height_col) * width_col;
    int coeff_w_col = (1 - stride_w * height_col * width_col);
    for (int h_col = h_col_start; h_col < h_col_end; ++h_col) {
      for (int w_col = w_col_start; w_col < w_col_end; ++w_col) {
        val += data_col[offset + h_col * coeff_h_col + w_col * coeff_w_col];
      }
    }
    data_im[index] = val;
  }
}

template <typename Dtype>
void col2im_gpu(const Dtype* data_col, const int channels,
    const int height, const int width, const int patch_h, const int patch_w,
    const int pad_h, const int pad_w, const int stride_h,
    const int stride_w, Dtype* data_im) {
  int height_col = (height + 2 * pad_h - patch_h) / stride_h + 1;
  int width_col = (width + 2 * pad_w - patch_w) / stride_w + 1;
  int num_kernels = channels * height * width;
  // To avoid involving atomic operations, we will launch one kernel per
  // bottom dimension, and then in the kernel add up the top dimensions.
  // NOLINT_NEXT_LINE(whitespace/operators)
  col2im_gpu_kernel<Dtype><<<CAFFE_GET_BLOCKS(num_kernels),
                             CAFFE_CUDA_NUM_THREADS>>>(
      num_kernels, data_col, height, width, channels, patch_h, patch_w,
      pad_h, pad_w, stride_h, stride_w,
      height_col, width_col, data_im);
  CUDA_POST_KERNEL_CHECK;
}

// Explicit instantiation
template void col2im_gpu<float>(const float* data_col, const int channels,
    const int height, const int width, const int patch_h, const int patch_w,
    const int pad_h, const int pad_w, const int stride_h,
    const int stride_w, float* data_im);
template void col2im_gpu<double>(const double* data_col, const int channels,
    const int height, const int width, const int patch_h, const int patch_w,
    const int pad_h, const int pad_w, const int stride_h,
    const int stride_w, double* data_im);

}  // namespace caffe
