#include "gpu_texture.h"
#include <epoxy/egl.h>
#include <vector>
extern "C" {
#include <libavutil/frame.h>
#include <libavutil/hwcontext.h>
#include <libavutil/hwcontext_drm.h>
}
namespace {
constexpr uint32_t fourcc(char a,char b,char c,char d){return uint32_t(a)|(uint32_t(b)<<8)|(uint32_t(c)<<16)|(uint32_t(d)<<24);}
GLuint shader(GLenum type,const char* source){GLuint result=glCreateShader(type);glShaderSource(result,1,&source,nullptr);glCompileShader(result);GLint okay=0;glGetShaderiv(result,GL_COMPILE_STATUS,&okay);if(!okay){glDeleteShader(result);return 0;}return result;}
GLuint program(){
  bool desktop=epoxy_is_desktop_gl();
  const char* vertexDesktop="#version 130\nout vec2 uv;void main(){vec2 p=vec2((gl_VertexID<<1)&2,gl_VertexID&2);uv=p;gl_Position=vec4(p*2.0-1.0,0.0,1.0);}";
  const char* vertexEs="#version 300 es\nout vec2 uv;void main(){vec2 p=vec2((gl_VertexID<<1)&2,gl_VertexID&2);uv=p;gl_Position=vec4(p*2.0-1.0,0.0,1.0);}";
  const char* fragmentDesktop="#version 130\nin vec2 uv;out vec4 color;uniform sampler2D yPlane;uniform sampler2D uvPlane;uniform vec3 offset;uniform mat3 matrix;void main(){vec3 yuv=vec3(texture(yPlane,uv).r,texture(uvPlane,uv).rg)+offset;color=vec4(matrix*yuv,1.0);}";
  const char* fragmentEs="#version 300 es\nprecision highp float;in vec2 uv;out vec4 color;uniform sampler2D yPlane;uniform sampler2D uvPlane;uniform vec3 offset;uniform mat3 matrix;void main(){vec3 yuv=vec3(texture(yPlane,uv).r,texture(uvPlane,uv).rg)+offset;color=vec4(matrix*yuv,1.0);}";
  GLuint vertex=shader(GL_VERTEX_SHADER,desktop?vertexDesktop:vertexEs),fragment=shader(GL_FRAGMENT_SHADER,desktop?fragmentDesktop:fragmentEs);
  if(!vertex||!fragment){if(vertex)glDeleteShader(vertex);if(fragment)glDeleteShader(fragment);return 0;}
  GLuint result=glCreateProgram();glAttachShader(result,vertex);glAttachShader(result,fragment);glLinkProgram(result);glDeleteShader(vertex);glDeleteShader(fragment);
  GLint okay=0;glGetProgramiv(result,GL_LINK_STATUS,&okay);if(!okay){glDeleteProgram(result);return 0;}return result;
}
}
bool McLinuxGpuTexture::render(AVFrame* source,GLuint output){
  if(!source || source->format!=AV_PIX_FMT_VAAPI || !epoxy_has_egl_extension(eglGetCurrentDisplay(),"EGL_EXT_image_dma_buf_import"))return false;
  auto display=eglGetCurrentDisplay();if(display==EGL_NO_DISPLAY)return false;
  AVFrame* mapped=av_frame_alloc();mapped->format=AV_PIX_FMT_DRM_PRIME;
  if(av_hwframe_map(mapped,source,AV_HWFRAME_MAP_READ|AV_HWFRAME_MAP_DIRECT)<0){av_frame_free(&mapped);return false;}
  auto* drm=reinterpret_cast<AVDRMFrameDescriptor*>(mapped->data[0]);
  if(!drm){av_frame_free(&mapped);return false;}
  struct Plane{int object;ptrdiff_t offset,pitch;};std::vector<Plane> planes;
  for(int layer=0;layer<drm->nb_layers;++layer)for(int p=0;p<drm->layers[layer].nb_planes;++p){auto plane=drm->layers[layer].planes[p];planes.push_back({plane.object_index,plane.offset,plane.pitch});}
  // NV12 only. 10-bit/P010 and unsupported layouts use the general fallback.
  bool nv12=(drm->nb_layers==1&&drm->layers[0].format==fourcc('N','V','1','2')) || (drm->nb_layers==2&&drm->layers[0].format==fourcc('R','8',' ',' ')&&drm->layers[1].format==fourcc('G','R','8','8'));
  if(!nv12||planes.size()!=2){av_frame_free(&mapped);return false;}
  EGLImageKHR images[2]={EGL_NO_IMAGE_KHR,EGL_NO_IMAGE_KHR};GLuint textures[2]{};
  bool okay=true;bool modifiers=epoxy_has_egl_extension(display,"EGL_EXT_image_dma_buf_import_modifiers");
  for(int i=0;i<2;++i){auto plane=planes[i];auto object=drm->objects[plane.object];
    std::vector<EGLint> attrs={EGL_WIDTH,i?(source->width+1)/2:source->width,EGL_HEIGHT,i?(source->height+1)/2:source->height,EGL_LINUX_DRM_FOURCC_EXT,static_cast<EGLint>(i?fourcc('G','R','8','8'):fourcc('R','8',' ',' ')),EGL_DMA_BUF_PLANE0_FD_EXT,object.fd,EGL_DMA_BUF_PLANE0_OFFSET_EXT,static_cast<EGLint>(plane.offset),EGL_DMA_BUF_PLANE0_PITCH_EXT,static_cast<EGLint>(plane.pitch)};
    if(modifiers&&object.format_modifier!=UINT64_MAX){attrs.insert(attrs.end(),{EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT,static_cast<EGLint>(object.format_modifier&0xffffffff),EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT,static_cast<EGLint>(object.format_modifier>>32)});}
    attrs.push_back(EGL_NONE);images[i]=eglCreateImageKHR(display,EGL_NO_CONTEXT,EGL_LINUX_DMA_BUF_EXT,nullptr,attrs.data());if(images[i]==EGL_NO_IMAGE_KHR){okay=false;break;}
  }
  GLint oldFbo=0,oldProgram=0,oldVao=0,oldActive=0,oldBindings[2]{},viewport[4]{};
  GLboolean oldBlend=glIsEnabled(GL_BLEND),oldScissor=glIsEnabled(GL_SCISSOR_TEST),oldDepth=glIsEnabled(GL_DEPTH_TEST);
  glGetIntegerv(GL_FRAMEBUFFER_BINDING,&oldFbo);glGetIntegerv(GL_CURRENT_PROGRAM,&oldProgram);glGetIntegerv(GL_VERTEX_ARRAY_BINDING,&oldVao);glGetIntegerv(GL_ACTIVE_TEXTURE,&oldActive);glGetIntegerv(GL_VIEWPORT,viewport);
  for(int i=0;i<2;++i){glActiveTexture(GL_TEXTURE0+i);glGetIntegerv(GL_TEXTURE_BINDING_2D,&oldBindings[i]);}
  if(okay){
    if(!program_)program_=program();
    if(!program_)okay=false;
    if(okay){
      if(!framebuffer_)glGenFramebuffers(1,&framebuffer_);
      if(!vao_)glGenVertexArrays(1,&vao_);
      glBindTexture(GL_TEXTURE_2D,output);
      if(width_!=source->width||height_!=source->height){width_=source->width;height_=source->height;glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA8,width_,height_,0,GL_RGBA,GL_UNSIGNED_BYTE,nullptr);}
      glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_LINEAR);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_LINEAR);
      glBindFramebuffer(GL_FRAMEBUFFER,framebuffer_);glFramebufferTexture2D(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,output,0);
      okay=glCheckFramebufferStatus(GL_FRAMEBUFFER)==GL_FRAMEBUFFER_COMPLETE;
      if(okay){
        glGenTextures(2,textures);for(int i=0;i<2;++i){glActiveTexture(GL_TEXTURE0+i);glBindTexture(GL_TEXTURE_2D,textures[i]);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_LINEAR);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_LINEAR);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_S,GL_CLAMP_TO_EDGE);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_T,GL_CLAMP_TO_EDGE);glEGLImageTargetTexture2DOES(GL_TEXTURE_2D,images[i]);}
        glUseProgram(program_);glUniform1i(glGetUniformLocation(program_,"yPlane"),0);glUniform1i(glGetUniformLocation(program_,"uvPlane"),1);
        bool full=source->color_range==AVCOL_RANGE_JPEG,bt709=source->colorspace==AVCOL_SPC_BT709;
        float y=full?1.0f:255.0f/219.0f,c=full?1.0f:255.0f/224.0f;
        float matrix[9]={y,y,y,0,c*(bt709?-0.187324f:-0.344136f),c*(bt709?1.8556f:1.772f),c*(bt709?1.5748f:1.402f),c*(bt709?-0.468124f:-0.714136f),0};
        glUniform3f(glGetUniformLocation(program_,"offset"),full?0:-16.0f/255.0f,-128.0f/255.0f,-128.0f/255.0f);glUniformMatrix3fv(glGetUniformLocation(program_,"matrix"),1,GL_FALSE,matrix);
        glDisable(GL_BLEND);glDisable(GL_SCISSOR_TEST);glDisable(GL_DEPTH_TEST);glViewport(0,0,width_,height_);glBindVertexArray(vao_);glDrawArrays(GL_TRIANGLES,0,3);
        okay=glGetError()==GL_NO_ERROR;
        // The exported surface must not return to the decoder before this draw
        // finishes. No decoded pixels cross the CPU boundary.
        glFinish();
      }
    }
  }
  glDeleteTextures(2,textures);for(int i=0;i<2;++i)if(images[i]!=EGL_NO_IMAGE_KHR)eglDestroyImageKHR(display,images[i]);
  glBindFramebuffer(GL_FRAMEBUFFER,oldFbo);glUseProgram(oldProgram);glBindVertexArray(oldVao);glViewport(viewport[0],viewport[1],viewport[2],viewport[3]);
  if(oldBlend)glEnable(GL_BLEND);
  if(oldScissor)glEnable(GL_SCISSOR_TEST);
  if(oldDepth)glEnable(GL_DEPTH_TEST);
  for(int i=0;i<2;++i){glActiveTexture(GL_TEXTURE0+i);glBindTexture(GL_TEXTURE_2D,oldBindings[i]);}glActiveTexture(oldActive);
  av_frame_free(&mapped);return okay;
}
