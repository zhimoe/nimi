#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <wincodec.h>
#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include "graphics.h"

struct NimiImage {
    HDC memory;
    HBITMAP bitmap;
    HGDIOBJ previous;
    uint32_t *pixels;
    int width, height;
};
#define NIMI_MAX_FONTS 128
typedef struct { wchar_t face[64]; int px, bold, quality; HFONT handle; } NimiFontEntry;
static NimiFontEntry font_cache[NIMI_MAX_FONTS];
static int font_cache_count;
static int font_cache_next;
static HDC measure_dc;
static HBITMAP measure_bitmap;

static int contains_cjk(const wchar_t *text, int count) {
    int i;
    for (i=0;i<count;i++) {
        wchar_t c=text[i];
        if ((c>=0x2E80 && c<=0x9FFF) || (c>=0xAC00 && c<=0xD7AF) ||
            (c>=0xF900 && c<=0xFAFF) || (c>=0xFF00 && c<=0xFFEF)) return 1;
    }
    return 0;
}
static void resolve_face(const wchar_t *family,const wchar_t *text,int count,wchar_t *out) {
    if (family && wcscmp(family,L"mono")==0) {
        lstrcpynW(out, contains_cjk(text,count)?L"NSimSun":L"Consolas", 64);
    } else if (family && family[0]) {
        lstrcpynW(out, family, 64);
    } else {
        lstrcpynW(out, L"Segoe UI", 64);
    }
}
static HFONT font(float size,int bold,const wchar_t *family,const wchar_t *text,int count,
                  int quality) {
    wchar_t face[64];
    int px=(int)(size+0.5f), i;
    if (px<1) px=1;
    resolve_face(family,text,count,face);
    for (i=0;i<font_cache_count;i++) {
        NimiFontEntry *e=&font_cache[i];
        if (e->px==px && e->bold==bold && e->quality==quality &&
            wcscmp(e->face,face)==0) return e->handle;
    }
    HFONT f=CreateFontW(-px,0,0,0,bold?FW_BOLD:FW_NORMAL,
        FALSE,FALSE,FALSE,DEFAULT_CHARSET,OUT_DEFAULT_PRECIS,CLIP_DEFAULT_PRECIS,
        quality,DEFAULT_PITCH,face);
    if (!f) {
        f=CreateFontW(-px,0,0,0,bold?FW_BOLD:FW_NORMAL,
            FALSE,FALSE,FALSE,DEFAULT_CHARSET,OUT_DEFAULT_PRECIS,CLIP_DEFAULT_PRECIS,
            quality,DEFAULT_PITCH,L"Segoe UI");
    }
    if (f) {
        NimiFontEntry *e=&font_cache[font_cache_next];
        if (e->handle) DeleteObject(e->handle);
        lstrcpynW(e->face,face,64);
        e->px=px; e->bold=bold; e->quality=quality; e->handle=f;
        font_cache_next=(font_cache_next+1)%NIMI_MAX_FONTS;
        if (font_cache_count<NIMI_MAX_FONTS) ++font_cache_count;
    }
    return f;
}
static HDC measurement_dc(void) {
    if (!measure_dc) {
        measure_dc=CreateCompatibleDC(NULL);
        if (measure_dc) {
            measure_bitmap=CreateCompatibleBitmap(measure_dc,1,1);
            if (measure_bitmap) SelectObject(measure_dc,measure_bitmap);
        }
    }
    return measure_dc;
}
void nimi_gdi_measure(const wchar_t *text, int count, float size, int bold,
                      const wchar_t *family, float *m) {
    HDC dc=measurement_dc();
    int own=0;
    if (!dc) { dc=CreateCompatibleDC(NULL); own=1; }
    HFONT f=font(size,bold,family,text,count,CLEARTYPE_QUALITY);
    HGDIOBJ old=SelectObject(dc,f);
    SIZE extent = {0}; TEXTMETRICW tm = {0};
    GetTextExtentPoint32W(dc,text,count,&extent); GetTextMetricsW(dc,&tm);
    m[0]=(float)extent.cx; m[1]=(float)tm.tmHeight;
    m[2]=(float)tm.tmAscent; m[3]=(float)tm.tmDescent; m[4]=(float)tm.tmExternalLeading;
    SelectObject(dc,old);
    if (own) DeleteDC(dc);
}
static void text_out(HDC dc,HFONT f,const wchar_t *text,int count,int x,int y,COLORREF color) {
    HGDIOBJ old=SelectObject(dc,f);
    SetBkMode(dc,TRANSPARENT); SetTextColor(dc,color); SetTextAlign(dc,TA_TOP|TA_LEFT);
    TextOutW(dc,x,y,text,count);
    SelectObject(dc,old);
}

/* Both software drawing paths blend a premultiplied, top-down DIB in device
   pixels. The caller saves the destination DC before switching to identity. */
static int create_dib(NimiImage *dib, int width, int height) {
    if (width <= 0 || height <= 0 ||
        (uint64_t)width * height > 64ull * 1024 * 1024) return 0;
    BITMAPINFO info = {0};
    info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    info.bmiHeader.biWidth = width;
    info.bmiHeader.biHeight = -height;
    info.bmiHeader.biPlanes = 1;
    info.bmiHeader.biBitCount = 32;
    info.bmiHeader.biCompression = BI_RGB;
    dib->memory = CreateCompatibleDC(NULL);
    if (!dib->memory) return 0;
    void *pixels = NULL;
    dib->bitmap = CreateDIBSection(dib->memory,&info,DIB_RGB_COLORS,&pixels,NULL,0);
    if (!dib->bitmap) return 0;
    dib->previous = SelectObject(dib->memory,dib->bitmap);
    if (!dib->previous) return 0;
    dib->width = width;
    dib->height = height;
    dib->pixels = pixels;
    return 1;
}

static void destroy_dib(NimiImage *dib) {
    if (!dib->memory) return;
    if (dib->previous) SelectObject(dib->memory,dib->previous);
    if (dib->bitmap) DeleteObject(dib->bitmap);
    DeleteDC(dib->memory);
}

static void blend_dib(HDC dc, const NimiImage *dib, const RECT *bounds, BYTE alpha) {
    BLENDFUNCTION blend = {AC_SRC_OVER,0,alpha,AC_SRC_ALPHA};
    AlphaBlend(dc,bounds->left,bounds->top,dib->width,dib->height,
               dib->memory,0,0,dib->width,dib->height,blend);
}

static NimiFloatPoint device_point(XFORM t, double x, double y) {
    return (NimiFloatPoint){x*t.eM11+y*t.eM21+t.eDx, x*t.eM12+y*t.eM22+t.eDy};
}

static int device_bounds(HDC dc, const NimiFloatPoint *points, RECT *bounds) {
    if (!SetGraphicsMode(dc, GM_ADVANCED) ||
        !ModifyWorldTransform(dc,NULL,MWT_IDENTITY) ||
        GetClipBox(dc,bounds) <= NULLREGION) return 0;
    double left=points[0].x, right=left, top=points[0].y, bottom=top;
    for (int i=0; i<4; ++i) {
        if (!isfinite(points[i].x) || !isfinite(points[i].y)) return 0;
        left=fmin(left,points[i].x); right=fmax(right,points[i].x);
        top=fmin(top,points[i].y); bottom=fmax(bottom,points[i].y);
    }
    left=fmax(bounds->left,floor(left)); right=fmin(bounds->right,ceil(right));
    top=fmax(bounds->top,floor(top)); bottom=fmin(bounds->bottom,ceil(bottom));
    if (left>=right || top>=bottom) return 0;
    *bounds=(RECT){(LONG)left,(LONG)top,(LONG)right,(LONG)bottom};
    return 1;
}

void nimi_gdi_text(void *context,const wchar_t *text,int count,float x,float y,
                   float size,int bold,unsigned color,unsigned alpha,const wchar_t *family) {
    if (!context || count<=0 || !alpha) return;
    HDC dc=context;
    HFONT f=font(size,bold,family,text,count,
                 alpha>=255?CLEARTYPE_QUALITY:ANTIALIASED_QUALITY);
    if (!f) return;
    if (alpha>=255) { text_out(dc,f,text,count,(int)x,(int)y,color); return; }

    int saved=SaveDC(dc);
    if (!saved) return;
    XFORM t={1,0,0,1,0,0};
    GetWorldTransform(dc,&t);
    HGDIOBJ old=SelectObject(dc,f);
    SIZE extent={0};
    GetTextExtentPoint32W(dc,text,count,&extent);
    SelectObject(dc,old);
    double left=(int)x-ceil(size), right=(int)x+extent.cx+ceil(size);
    double top=(int)y-ceil(size), bottom=(int)y+extent.cy+ceil(size);
    NimiFloatPoint corners[4]={device_point(t,left,top),device_point(t,right,top),
                              device_point(t,right,bottom),device_point(t,left,bottom)};
    RECT bounds;
    NimiImage mask={0};
    if (device_bounds(dc,corners,&bounds) &&
        create_dib(&mask,bounds.right-bounds.left,bounds.bottom-bounds.top)) {
        PatBlt(mask.memory,0,0,mask.width,mask.height,BLACKNESS);
        SetGraphicsMode(mask.memory,GM_ADVANCED);
        t.eDx-=bounds.left; t.eDy-=bounds.top;
        SetWorldTransform(mask.memory,&t);
        text_out(mask.memory,f,text,count,(int)x,(int)y,RGB(255,255,255));
        GdiFlush();
        for (size_t i=0, n=(size_t)mask.width*mask.height; i<n; ++i) {
            unsigned a=mask.pixels[i]&255;
            mask.pixels[i]=(a<<24) | ((GetRValue(color)*a/255)<<16) |
                           ((GetGValue(color)*a/255)<<8) | (GetBValue(color)*a/255);
        }
        ModifyWorldTransform(mask.memory,NULL,MWT_IDENTITY);
        blend_dib(dc,&mask,&bounds,(BYTE)alpha);
    }
    destroy_dib(&mask);
    RestoreDC(dc,saved);
}
void nimi_gdi_rect(void *context,int x,int y,int w,int h,int radius,unsigned color,unsigned alpha) {
    if (w<=0 || h<=0 || !alpha) return;
    HDC dc=context;
    int saved=SaveDC(dc);
    if(radius>0) {
        POINT points[3]={{x,y},{x+w+1,y+h+1},{x+radius*2,y+radius*2}};
        LPtoDP(dc,points,3);
        HRGN region=CreateRoundRectRgn(points[0].x,points[0].y,points[1].x,points[1].y,
                                       points[2].x-points[0].x,points[2].y-points[0].y);
        ExtSelectClipRgn(dc,region,RGN_AND); DeleteObject(region);
    }
    HBRUSH brush=CreateSolidBrush(color);
    if(alpha>=255) { RECT r={x,y,x+w,y+h}; FillRect(dc,&r,brush); }
    else {
        HDC source=CreateCompatibleDC(dc); HBITMAP bitmap=CreateCompatibleBitmap(dc,1,1);
        HGDIOBJ old=SelectObject(source,bitmap); RECT r={0,0,1,1}; FillRect(source,&r,brush);
        BLENDFUNCTION blend={AC_SRC_OVER,0,(BYTE)alpha,0};
        AlphaBlend(dc,x,y,w,h,source,0,0,1,1,blend);
        SelectObject(source,old); DeleteObject(bitmap); DeleteDC(source);
    }
    DeleteObject(brush); RestoreDC(dc,saved);
}
void nimi_gdi_clip(void *dc,int x,int y,int w,int h) { SaveDC(dc); IntersectClipRect(dc,x,y,x+w,y+h); }
void nimi_gdi_clip_round(void *dc,int x,int y,int w,int h,int radius) {
    HDC context=dc;
    if (radius<=0) { nimi_gdi_clip(dc,x,y,w,h); return; }
    if (w<=0 || h<=0) { SaveDC(context); IntersectClipRect(context,x,y,x,y); return; }
    int saved=SaveDC(context);
    int diameter=radius*2;
    if (diameter>w) diameter=w;
    if (diameter>h) diameter=h;
    if (!BeginPath(context)) { RestoreDC(context,saved); return; }
    RoundRect(context,x,y,x+w,y+h,diameter,diameter);
    EndPath(context);
    if (!SelectClipPath(context,RGN_AND)) RestoreDC(context,saved);
}
void nimi_gdi_restore(void *dc) { RestoreDC(dc,-1); }

void nimi_gdi_polygon(void *context,const NimiPoint *points,int count,unsigned color,unsigned alpha) {
    if(!context || !points || count<3 || !alpha) return;
    HDC dc=context;
    POINT *device=malloc((size_t)count*sizeof(POINT));
    if(!device) return;
    int minX=points[0].x, minY=points[0].y, maxX=minX, maxY=minY;
    for(int i=0;i<count;i++) {
        device[i].x=points[i].x; device[i].y=points[i].y;
        if(points[i].x<minX) minX=points[i].x;
        if(points[i].x>maxX) maxX=points[i].x;
        if(points[i].y<minY) minY=points[i].y;
        if(points[i].y>maxY) maxY=points[i].y;
    }
    /* Build the clip path in logical coordinates so the DC world transform
       (DPI scaling) applies to both opaque fills and AlphaBlend. */
    int saved=SaveDC(dc);
    BeginPath(dc);
    Polygon(dc,device,count);
    EndPath(dc);
    if(!SelectClipPath(dc,RGN_AND)) { RestoreDC(dc,saved); free(device); return; }
    int w=maxX-minX, h=maxY-minY;
    if(w>0 && h>0) {
        if(alpha>=255) {
            HBRUSH brush=CreateSolidBrush(color);
            RECT r={minX,minY,maxX,maxY};
            FillRect(dc,&r,brush);
            DeleteObject(brush);
        } else {
            HDC source=CreateCompatibleDC(dc);
            HBITMAP bitmap=CreateCompatibleBitmap(dc,1,1);
            HGDIOBJ old=SelectObject(source,bitmap);
            RECT one={0,0,1,1};
            HBRUSH brush=CreateSolidBrush(color);
            FillRect(source,&one,brush);
            DeleteObject(brush);
            BLENDFUNCTION blend={AC_SRC_OVER,0,(BYTE)alpha,0};
            AlphaBlend(dc,minX,minY,w,h,source,0,0,1,1,blend);
            SelectObject(source,old); DeleteObject(bitmap); DeleteDC(source);
        }
    }
    RestoreDC(dc,saved);
    free(device);
}

NimiImage *nimi_gdi_image_load(const wchar_t *path) {
    if(!path || !*path) return NULL;
    /* WIC is COM-based. RPC_E_CHANGED_MODE means another apartment already
       initialized this thread; the factory is still usable. */
    HRESULT hr=CoInitializeEx(NULL,COINIT_APARTMENTTHREADED|COINIT_DISABLE_OLE1DDE);
    int uninitialize=SUCCEEDED(hr);
    if(FAILED(hr) && hr!=RPC_E_CHANGED_MODE) return NULL;
    IWICImagingFactory *factory=NULL;
    IWICBitmapDecoder *decoder=NULL;
    IWICBitmapFrameDecode *frame=NULL;
    IWICFormatConverter *converter=NULL;
    NimiImage *image=NULL;
    hr=CoCreateInstance(&CLSID_WICImagingFactory,NULL,CLSCTX_INPROC_SERVER,
                        &IID_IWICImagingFactory,(void **)&factory);
    if(FAILED(hr)) goto done;
    hr=IWICImagingFactory_CreateDecoderFromFilename(factory,path,NULL,GENERIC_READ,
        WICDecodeMetadataCacheOnDemand,&decoder);
    if(FAILED(hr)) goto done;
    hr=IWICBitmapDecoder_GetFrame(decoder,0,&frame);
    if(FAILED(hr)) goto done;
    hr=IWICImagingFactory_CreateFormatConverter(factory,&converter);
    if(FAILED(hr)) goto done;
    hr=IWICFormatConverter_Initialize(converter,(IWICBitmapSource *)frame,
        &GUID_WICPixelFormat32bppPBGRA,WICBitmapDitherTypeNone,NULL,0.0,
        WICBitmapPaletteTypeCustom);
    if(FAILED(hr)) goto done;
    UINT width=0,height=0;
    hr=IWICBitmapSource_GetSize((IWICBitmapSource *)converter,&width,&height);
    if(FAILED(hr) || !width || !height || width>16384 || height>16384 ||
       (unsigned long long)width*height > 64ull*1024*1024) goto done;
    image=calloc(1,sizeof(*image));
    if(!image) { hr=E_OUTOFMEMORY; goto done; }
    if(!create_dib(image,(int)width,(int)height)) { hr=E_OUTOFMEMORY; goto done; }
    hr=IWICBitmapSource_CopyPixels((IWICBitmapSource *)converter,NULL,
        width*4,width*height*4,(BYTE *)image->pixels);
done:
    if(converter) IWICFormatConverter_Release(converter);
    if(frame) IWICBitmapFrameDecode_Release(frame);
    if(decoder) IWICBitmapDecoder_Release(decoder);
    if(factory) IWICImagingFactory_Release(factory);
    if(uninitialize) CoUninitialize();
    if(FAILED(hr)) {
        nimi_gdi_image_free(image);
        return NULL;
    }
    return image;
}

void nimi_gdi_image_free(NimiImage *image) {
    if(!image) return;
    destroy_dib(image);
    free(image);
}

int nimi_gdi_image_width(const NimiImage *image) { return image?image->width:0; }
int nimi_gdi_image_height(const NimiImage *image) { return image?image->height:0; }

int nimi_gdi_image_draw(void *context,const NimiImage *image,int x,int y,int w,int h,
                        int sourceX,int sourceY,int sourceWidth,int sourceHeight) {
    if(!context || !image || w<=0 || h<=0 || sourceWidth<=0 || sourceHeight<=0) return 0;
    HDC dc=context;
    int previous=SetStretchBltMode(dc,HALFTONE);
    BLENDFUNCTION blend={AC_SRC_OVER,0,255,AC_SRC_ALPHA};
    BOOL ok=AlphaBlend(dc,x,y,w,h,image->memory,sourceX,sourceY,
                       sourceWidth,sourceHeight,blend);
    SetStretchBltMode(dc,previous);
    return ok?1:0;
}

typedef struct {
    NimiFloatPoint origin;
    double ux, uy, vx, vy, inverse;
} ImageTriangle;

static ImageTriangle image_triangle(NimiFloatPoint a, NimiFloatPoint b, NimiFloatPoint c) {
    ImageTriangle triangle={a,b.x-a.x,b.y-a.y,c.x-a.x,c.y-a.y,0};
    double area=triangle.ux*triangle.vy-triangle.uy*triangle.vx;
    if (fabs(area)>1e-8) triangle.inverse=1.0/area;
    return triangle;
}

static int triangle_weights(const ImageTriangle *t, double x, double y, double *u, double *v) {
    if (!t->inverse) return 0;
    x-=t->origin.x; y-=t->origin.y;
    *u=(x*t->vy-y*t->vx)*t->inverse;
    *v=(y*t->ux-x*t->uy)*t->inverse;
    return *u>=-1e-9 && *v>=-1e-9 && *u+*v<=1+1e-9;
}

static uint32_t image_sample(const NimiImage *image, const RECT *crop, double x, double y) {
    /* Coordinates describe pixel edges; place each sample at its pixel center. */
    x=fmax(crop->left,fmin(crop->right-1,x-0.5));
    y=fmax(crop->top,fmin(crop->bottom-1,y-0.5));
    int left=(int)x, top=(int)y;
    int right=left+1<crop->right?left+1:left;
    int bottom=top+1<crop->bottom?top+1:top;
    double fx=x-left, fy=y-top;
    const uint32_t *row1=image->pixels+(size_t)top*image->width;
    const uint32_t *row2=image->pixels+(size_t)bottom*image->width;
    uint32_t result=0;
    for (int shift=0; shift<32; shift+=8) {
        double upper=((row1[left]>>shift)&255)*(1-fx)+((row1[right]>>shift)&255)*fx;
        double lower=((row2[left]>>shift)&255)*(1-fx)+((row2[right]>>shift)&255)*fx;
        result|=(uint32_t)(upper*(1-fy)+lower*fy+0.5)<<shift;
    }
    return result;
}

void nimi_gdi_image_quad(void *context,const NimiImage *image,
    float x,float y,float w,float h,const NimiFloatPoint *quad) {
    if (!context || !image || !quad || !isfinite(x) || !isfinite(y) ||
        !isfinite(w) || !isfinite(h) || w<=0 || h<=0) return;
    double left=fmax(0,floor(x)), top=fmax(0,floor(y));
    double right=fmin(image->width,ceil((double)x+w));
    double bottom=fmin(image->height,ceil((double)y+h));
    if (left>=right || top>=bottom) return;
    RECT crop={(LONG)left,(LONG)top,(LONG)right,(LONG)bottom};

    HDC dc=context;
    int saved=SaveDC(dc);
    if (!saved) return;
    XFORM t={1,0,0,1,0,0};
    GetWorldTransform(dc,&t);
    NimiFloatPoint points[4];
    for (int i=0; i<4; ++i) points[i]=device_point(t,quad[i].x,quad[i].y);
    RECT bounds;
    NimiImage layer={0};
    if (device_bounds(dc,points,&bounds) &&
        create_dib(&layer,bounds.right-bounds.left,bounds.bottom-bounds.top)) {
        ImageTriangle first=image_triangle(points[0],points[1],points[2]);
        ImageTriangle second=image_triangle(points[0],points[2],points[3]);
        for (int row=0; row<layer.height; ++row) {
            uint32_t *out=layer.pixels+(size_t)row*layer.width;
            for (int col=0; col<layer.width; ++col) {
                double px=bounds.left+col+0.5, py=bounds.top+row+0.5, u, v;
                if (triangle_weights(&first,px,py,&u,&v)) {
                    out[col]=image_sample(image,&crop,left+(u+v)*(right-left),
                                         top+v*(bottom-top));
                } else if (triangle_weights(&second,px,py,&u,&v)) {
                    out[col]=image_sample(image,&crop,left+u*(right-left),
                                         top+(u+v)*(bottom-top));
                } else out[col]=0;
            }
        }
        blend_dib(dc,&layer,&bounds,255);
    }
    destroy_dib(&layer);
    RestoreDC(dc,saved);
}
