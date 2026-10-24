//! 拥有帧引用、像素转换上下文与导出图像；不接触捕获或输出生命周期。

use super::ff;
use std::{
    ffi::{c_int, c_void},
    ptr,
};

pub(super) struct Frame(pub(super) *mut ff::AVFrame);
impl Drop for Frame {
    fn drop(&mut self) {
        unsafe {
            ff::av_frame_free(&mut self.0);
        }
    }
}

#[derive(Default)]
pub(super) struct Conversion {
    scaler: *mut ff::SwsContext,
}
impl Drop for Conversion {
    fn drop(&mut self) {
        unsafe {
            ff::sws_freeContext(self.scaler);
        }
    }
}
impl Conversion {
    pub(super) unsafe fn copy(
        &mut self,
        input: *mut ff::AVFrame,
        max_width: u32,
        max_height: u32,
        format: ff::AVPixelFormat,
        out: *mut ff::mc_image,
    ) -> c_int {
        if out.is_null() {
            return -1;
        }
        *out = std::mem::zeroed();
        // 借用调用方的帧引用；本模块仅拥有可选的硬件下载帧。
        let frame = std::mem::ManuallyDrop::new(Frame(input));
        if frame.0.is_null() {
            return 1;
        }
        let mut software = Frame(ptr::null_mut());
        let description = ff::av_pix_fmt_desc_get((*frame.0).format);
        if !description.is_null()
            && ((*description).flags & ff::AV_PIX_FMT_FLAG_HWACCEL as u64) != 0
        {
            software.0 = ff::av_frame_alloc();
            if software.0.is_null() {
                return ff::MC_ENOMEM;
            }
            let result = ff::av_hwframe_transfer_data(software.0, frame.0, 0);
            if result < 0 {
                return result;
            }
            let result = ff::av_frame_copy_props(software.0, frame.0);
            if result < 0 {
                return result;
            }
        }
        let source = if software.0.is_null() {
            &*frame.0
        } else {
            &*software.0
        };
        if source.width <= 0
            || source.height <= 0
            || source.width > crate::MAX_VIDEO_DIMENSION as i32
            || source.height > crate::MAX_VIDEO_DIMENSION as i32
        {
            return -1;
        }
        let mut scale = 1.0_f64;
        if max_width != 0 && source.width as u32 > max_width {
            scale = scale.min(max_width as f64 / source.width as f64);
        }
        if max_height != 0 && source.height as u32 > max_height {
            scale = scale.min(max_height as f64 / source.height as f64);
        }
        (*out).width = ((source.width as f64 * scale) as u32).max(1);
        (*out).height = ((source.height as f64 * scale) as u32).max(1);
        (*out).stride = (*out).width as usize * 4;
        (*out).size = (*out).stride * (*out).height as usize;
        (*out).rgba = ff::av_malloc((*out).size) as *mut u8;
        if (*out).rgba.is_null() {
            *out = std::mem::zeroed();
            return ff::MC_ENOMEM;
        }
        self.scaler = ff::sws_getCachedContext(
            self.scaler,
            source.width,
            source.height,
            source.format,
            (*out).width as c_int,
            (*out).height as c_int,
            format,
            ff::SWS_FAST_BILINEAR as c_int,
            ptr::null_mut(),
            ptr::null_mut(),
            ptr::null(),
        );
        let result = if self.scaler.is_null() {
            -1
        } else {
            let matrix = match source.colorspace {
                ff::AVCOL_SPC_BT709 => ff::SWS_CS_ITU709,
                ff::AVCOL_SPC_BT2020_NCL | ff::AVCOL_SPC_BT2020_CL => ff::SWS_CS_BT2020,
                ff::AVCOL_SPC_UNSPECIFIED => ff::SWS_CS_ITU709,
                _ => ff::SWS_CS_ITU601,
            };
            let coefficients = ff::sws_getCoefficients(matrix as c_int);
            ff::sws_setColorspaceDetails(
                self.scaler,
                coefficients,
                (source.color_range == ff::AVCOL_RANGE_JPEG) as c_int,
                coefficients,
                1,
                0,
                1 << 16,
                1 << 16,
            );
            let planes = [
                (*out).rgba,
                ptr::null_mut(),
                ptr::null_mut(),
                ptr::null_mut(),
            ];
            let strides = [(*out).stride as c_int, 0, 0, 0];
            ff::sws_scale(
                self.scaler,
                source.data.as_ptr() as *const *const u8,
                source.linesize.as_ptr(),
                0,
                source.height,
                planes.as_ptr(),
                strides.as_ptr(),
            )
        };
        if result < 0 {
            free(out);
            result
        } else {
            0
        }
    }
}

pub(super) unsafe fn free(image: *mut ff::mc_image) {
    if !image.is_null() {
        ff::av_free((*image).rgba as *mut c_void);
        *image = std::mem::zeroed();
    }
}
