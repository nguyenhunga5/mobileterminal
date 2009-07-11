// VT100TextView.m
// VT100

#import "VT100TextView.h"
#import "ColorMap.h"
#import "VT100.h"

// Buffer space used to draw any particular row.  We assume that drawRect is
// only ever called from the main thread, so we can share a buffer between
// calls.
static const int kMaxRowBufferSize = 200;

extern void CGFontGetGlyphsForUnichars(CGFontRef, unichar[], CGGlyph[], size_t);

@interface VT100TextView (RefreshDelegate) <ScreenBufferRefreshDelegate>
- (void)refresh;
@end

@implementation VT100TextView

@synthesize buffer;
@synthesize colorMap;

- (id)initWithCoder:(NSCoder *)decoder
{
  self = [super initWithCoder:decoder];
  if (self != nil) {
    VT100* vt100 = [[VT100 alloc] init];
    [vt100 setRefreshDelegate:self];
    buffer = vt100;
    [self setFont:[UIFont systemFontOfSize:[UIFont smallSystemFontSize]]];
    colorMap = [[ColorMap alloc] init];
    glyphBuffer = (CGGlyph*)malloc(sizeof(CGGlyph) * kMaxRowBufferSize);
  }
  return self;
}

- (void)dealloc
{
  CFRelease(cgFont);
  [colorMap release];
  [buffer release];
  [font release];
  [super dealloc];
}

- (void)setFont:(UIFont*)newFont;
{
  // Release the old font, if it exists (this is a no-op otherwise)
  CGFontRelease(cgFont);
  [font release];
  
  // Retain the new font, and cache some of its properties that are expensive
  // to look up every time we draw.
  font = newFont;
  [font retain];  
  cgFont = CGFontCreateWithFontName((CFStringRef)font.fontName);
  NSAssert(font != NULL, @"Error CGFontCreateWithFontName");
  
  // This assumes a monospaced font, which is probably not a safe assumption.
  // Determine size of the screen based on the font size
  fontSize = [@"A" sizeWithFont:font];
  CGSize frameSize = [self frame].size;
  ScreenSize size;
  size.width = (int)(frameSize.width / fontSize.width);
  size.height = (int)(frameSize.height / fontSize.height);
  [buffer setScreenSize:size];
}

- (int)width
{
  return [buffer screenSize].width;
}

- (int)height
{
  return [buffer screenSize].height;
}

// Draw some glyphs on the screen.  The glyphs pointer is typically a pointer
// into the glyphBuffer.
- (void)drawCharacters:(CGGlyph*)glyphs
            withLength:(int)length
             withColor:(CGColorRef)color
               atPoint:(CGPoint)point
            forContext:(CGContextRef)context
{
  CGContextSetFillColorWithColor(context, color);
  CGContextShowGlyphsAtPoint(context, point.x, point.y, glyphs, length);
}

// Populate the glyphBuffer with screen characters for the specified row.  Do
// this conversion once for the entire row then draw the glyphs on the
// screen from the buffer batched by adjacent glyphs of the same color.  Returns
// the actual number of glyphs populated for the row.
- (int)fillGlyphBufferForRow:(screen_char_t*)row withSize:(int)length
{
  NSParameterAssert(length < kMaxRowBufferSize);
  unichar unicharBuffer[kMaxRowBufferSize];
  int j;
  for (j = 0; j < length; ++j) {
    // Assume there is nothing left to draw on the screen after the first null.
    // TODO(allen): Is this a correct assumption?
    if (row[j].ch == '\0') {
      break;
    }
    unicharBuffer[j] = row[j].ch;
  }
  CGFontGetGlyphsForUnichars(cgFont, unicharBuffer, glyphBuffer, j);
  return j;
}

- (int)adjacentCharactersWithSameColor:(screen_char_t*)data withSize:(int)length
{
  int i = 1;
  for (i = 1; i < length; ++i) {
    if (data[0].fg_color != data[i].fg_color) {
      break;
    }
  }
  return i;
}

// TODO(allen): This is by no means complete! The old PTYTextView does a lot
// more stuff that needs to be ported -- and it also does it quite efficiently.
- (void)drawRect:(CGRect)rect
{
  // TODO(allen): We currently draw the entire control instead of just the
  // rect that we were asked to update
  NSLog(@"(%f, %f) -> (%f, %f)", rect.origin.x, rect.origin.y,
        rect.size.width, rect.size.height);
  
  NSAssert(font != NULL, @"No font specified");
  
  CGContextRef context = UIGraphicsGetCurrentContext();
  CGContextSetFont(context, cgFont);
  CGContextSetFontSize(context, font.pointSize);
  
  // By default, text is drawn upside down.  Apply a transformation to turn
  // orient the text correctly.
  CGAffineTransform xform = CGAffineTransformMake(1.0, 0.0, 0.0, -1.0, 0.0, 0.0);
  CGContextSetTextMatrix(context, xform);
  
  // TODO(allen): Draw background color
  // TODO(allen): Draw a cursor

  // Walk through the screen and output all characeters to the display
  ScreenSize screenSize = [buffer screenSize];  
  for (int i = 0; i < screenSize.height; ++i) {
    screen_char_t* row = [buffer bufferForRow:i];    
    // Convert all on screen characters to their equivalent glyphs at once.
    int glpyhs = [self fillGlyphBufferForRow:row withSize:screenSize.width];
    
    // In order to minimize the number of calls into CoreGraphics routines for
    // drawing text, walk each character until a different foreground color is
    // found.
    int j = 0;
    while (j < glpyhs) {
      int adjacent = [self adjacentCharactersWithSameColor:(row + j)
                                                  withSize:(glpyhs - j)];
      CGPoint point = CGPointMake(j * fontSize.width, font.pointSize * (i + 1));
      CGColorRef color = [[colorMap color:row[j].fg_color] CGColor];
      [self drawCharacters:(glyphBuffer + j)
                withLength:adjacent
                 withColor:color
                   atPoint:point
                forContext:context];
      j += adjacent;
    }
  }
}

- (void)readInputStream:(NSData*)data;
{
  // Simply forward the input stream down the VT100 processor.  When it notices
  // changes to the screen, it should invoke our refresh delegate below.
  // TODO(aporter): The ScreenBuffer interface should just deal with NSData
  // directly.
  [buffer readInputStream:(const char*)[data bytes] withLength:[data length]];
}

@end

@implementation VT100TextView (RefreshDelegate)

- (void)refresh
{
  // TODO(aporter): Call setNeedsDisplayInRect for only the dirty bits
  [self setNeedsDisplay];
}

@end