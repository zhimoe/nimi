#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <wincodec.h>
#include <stdlib.h>
#include "graphics.h"

struct NimiImage {
    HDC memory;
    HBITMAP bitmap;
    HGDIOBJ previous;
    int width, height;
};
static HFONT font(float size, int bold) {
    return CreateFontW(-(int)(size + 0.5f),0,0,0,bold?FW_BOLD:FW_NORMAL,
        FALSE,FALSE,FALSE,DEFAULT_CHARSET,OUT_DEFAULT_PRECIS,CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY,DEFAULT_PITCH,L"Segoe UI");
}
void nimi_gdi_measure(const wchar_t *text, int count, float size, int bold, float *m) {
    HDC dc = CreateCompatibleDC(NULL);
    HFONT f = font(size,bold); HGDIOBJ old = SelectObject(dc,f);
    SIZE extent = {0}; TEXTMETRICW tm = {0};
    GetTextExtentPoint32W(dc,text,count,&extent); GetTextMetricsW(dc,&tm);
    m[0]=(float)extent.cx; m[1]=(float)tm.tmHeight;
    m[2]=(float)tm.tmAscent; m[3]=(float)tm.tmDescent; m[4]=(float)tm.tmExternalLeading;
    SelectObject(dc,old); DeleteObject(f); DeleteDC(dc);
}
void nimi_gdi_text(void *context,const wchar_t *text,int count,float x,float y,float size,int bold,unsigned color) {
    HDC dc=context; HFONT f=font(size,bold); HGDIOBJ old=SelectObject(dc,f);
    SetBkMode(dc,TRANSPARENT); SetTextColor(dc,color); SetTextAlign(dc,TA_TOP|TA_LEFT);
    TextOutW(dc,(int)x,(int)y,text,count);
    SelectObject(dc,old); DeleteObject(f);
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
    image->width=(int)width; image->height=(int)height;
    BITMAPINFO info={0};
    info.bmiHeader.biSize=sizeof(BITMAPINFOHEADER);
    info.bmiHeader.biWidth=image->width;
    info.bmiHeader.biHeight=-image->height; /* top-down, matching WIC rows */
    info.bmiHeader.biPlanes=1;
    info.bmiHeader.biBitCount=32;
    info.bmiHeader.biCompression=BI_RGB;
    void *bits=NULL;
    image->memory=CreateCompatibleDC(NULL);
    if(!image->memory) { hr=E_OUTOFMEMORY; goto done; }
    image->bitmap=CreateDIBSection(image->memory,&info,DIB_RGB_COLORS,&bits,NULL,0);
    if(!image->bitmap || !bits) { hr=E_OUTOFMEMORY; goto done; }
    image->previous=SelectObject(image->memory,image->bitmap);
    hr=IWICBitmapSource_CopyPixels((IWICBitmapSource *)converter,NULL,
        (UINT)image->width*4,(UINT)(image->width*image->height*4),(BYTE *)bits);
    if(FAILED(hr)) goto done;
    goto done;
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
    if(image->memory) {
        if(image->previous) SelectObject(image->memory,image->previous);
        if(image->bitmap) DeleteObject(image->bitmap);
        DeleteDC(image->memory);
    }
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
