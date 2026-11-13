#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include "graphics.h"
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
