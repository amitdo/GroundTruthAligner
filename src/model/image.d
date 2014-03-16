// -*- mode: d -*-
/*
 *       image.d
 *
 *       Copyright 2014 Antonio-M. Corbi Bellot <antonio.corbi@ua.es>
 *     
 *       This program is free software; you can redistribute it and/or modify
 *       it under the terms of the GNU  General Public License as published by
 *       the Free Software Foundation; either version 3 of the License, or
 *       (at your option) any later version.
 *     
 *       This program is distributed in the hope that it will be useful,
 *       but WITHOUT ANY WARRANTY; without even the implied warranty of
 *       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *       GNU General Public License for more details.
 *      
 *       You should have received a copy of the GNU General Public License
 *       along with this program; if not, write to the Free Software
 *       Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
 *       MA 02110-1301, USA.
 */

module model.image;

////////////////
// STD + CORE //
////////////////
import std.stdio;
import std.math;
import core.memory: GC;		// We need to play with the garbage collector
import std.conv;
import std.signals;
import std.algorithm;

/////////
// GDK //
/////////
import gdk.Pixbuf;
import gdk.Cairo;

///////////
// CAIRO //
///////////
import cairo.Context;
import cairo.ImageSurface;
import cairo.Surface;

/////////
// MVC //
/////////
//import mvc.modelview;

////////////////
// Code begin //
//////////////////////////////////////////////////////////////////////

/**
 * Class Image: This class represents an image. Normally this image
 * will be a scanned page.
 *
 */
class Image {
  
public:
  
  /////////////////
  // Constructor //
  /////////////////
  this () {
    init_instance_variables ();
  }
  
  /////////////////
  // Destructor  //
  /////////////////
  ~this () {
    debug writeln ("Destroying Image!");
  }

  ///////////
  // Enums //
  ///////////
  enum Color { BLACK = 0, WHITE = 255 };

  /////////////
  // Signals //
  /////////////////////////////////////////////////////////////////////////
  mixin Signal!(string, float) signal_progress;
  /////////////////////////////////////////////////////////////////////////

  /////////////
  // Methods //
  /////////////////////////////////////////////////////////////////////////

  @property Pixbuf data () { return mpxbf_rotated; }

  @property int width () {
    if (mpxbf !is null)
      return mpxbf.getWidth();
    else
      return -1;
  }

  @property int height () {
    if (mpxbf !is null)
      return mpxbf.getHeight();
    else
      return -1;
  }

  /**
   * Returns:
   *     the line with the maximum number of black pixels of all
   *     scanned lines
   */
  @property int blackest_line () { return mlwmbp; }

  /**
   * Returns:
   *     The number of black pixels in the line with most of them.
   */
  @property int bpx_in_blackest_line () { return mbppl[mlwmbp]; }

  /**
   * Returns:
   *   The X coordinate for the left margin.
   */
  @property int left_margin () { return mlmargin; }

  /**
   * Returns:
   *   The X coordinate for the rightt margin.
   */
  @property int right_margin () { return mrmargin; }

  /**
   * Returns the mean and the variance of the black pixels from the
   * Image.
   */
  void get_mean_variance_bpixels (out float mean, out float variance) {
    mean = variance = 0.0;
    if (mbppl !is null) {
      // Mean
      for (int i = 0; i<mbppl.length ; i++) {
	mean += mbppl[i];
      }
      mean /= mbppl.length;

      // Variance
      for (int i = 0; i<mbppl.length ; i++) {
	variance += (mbppl[i]-mean)^^2.0;
      }
      variance /= mbppl.length;
    }
  }

  /**
   * Counts black pixels in one line.
   *
   * Params:
   *   y = The line to search black pixels in.
   *   
   * Returns:
   *     the number of black pixels in line 'y'.
   */
  int get_black_pixels_in_line (int y) 
    in { 
      assert (y < mh);
    }
  body {
    if (mpxbf !is null) return mbppl[y];
    return 0;
  }

  /**
   * Counts how many COLOR pixels are in the image.
   * 
   * Params:
   *    cl = The color to search for.
   */
  int count_color_pixels (Color cl) {
    char r,g,b;
    int c = 0;
    
    for (int x = 0; x < mw; x++)
      for (int y = 0; y < mh; y++) {
	get_rgb (x, y, r, g, b);
	if (r == cl && g == cl && b == cl)
	  c++;
      }
    return c;
  }
  
  /**
   * Loads the image in filename into the pixbuf.
   */
  void load_from_file (string filename) {

    if (filename == "") return;

    signal_progress.emit ("Loading image", 0.25);

    if (mpxbf !is null) { mpxbf.unref(); }
    if (mpxbf_rotated !is null) { mpxbf_rotated.unref(); }

    mpxbf = new Pixbuf (filename);

    if (mpxbf !is null) {

      if (mpxbf_rotated !is null) { mpxbf_rotated.unref(); }
      mpxbf_rotated = mpxbf.copy ();	// We save the original image
					// in case we rotate/scale it.
      get_image_parameters ();
      //count_black_pixels_per_line ();  // <- invoked inside "get_image_parameters"

      debug writefln ("Pixbuf loaded:\nImage is %u X %u pixels\n", 
		      mpxbf.getWidth(), 
		      mpxbf.getHeight());
    } else {
      init_instance_variables ();
    }
  }

  /**
   * Get the RGB values from pixel x,y,
   */
  void get_rgb (in int x, in int y, out char r, out char g, out char b) {
    if (mpxbf_rotated !is null) {
      if ( (x < mw) && (y < mh) ) {
	  char* e = cast(char*) (mbase + (y * mrs) + (x * mnc));
	  r = e[0];
	  g = e[1];
	  b = e[2];
	} else r = g = b = 0;
    } else r = g = b = 0;
  }

  /**
   * Set the RGB values for pixel x,y,
   */
  void set_rgb (in int x, in int y, in char r, in char g, in char b) {
    if (mpxbf_rotated !is null) {
      if ( (x < mw) && (y < mh) ) {
	  char* e = cast(char*) (mbase + (y * mrs) + (x * mnc));
	  e[0] = r;
	  e[1] = g;
	  e[2] = b;
	}
    }
  }

  /**
   * Checks for a valid image loaded.
   */
  @property bool is_valid () {
    return mpxbf !is null;
  }

  /**
   * Rotate the image by 'deg' degrees.
   * 
   * Params:
   *   deg = The number of degrees to rotate the image.
   */
  public void rotate_by (float deg) {

    if (mpxbf !is null) {
      //mpxbf = mpxbf_orig;

      CairoFormat  fmt = mpxbf.getHasAlpha () ? CairoFormat.ARGB32 : CairoFormat.RGB24;
      //int            w = mpxbf.getWidth ();
      //int            h = mpxbf.getHeight ();
      ImageSurface ims = ImageSurface.create (fmt, mw, mh);
      Context      ctx = Context.create (ims);
      float        rad = deg * PI / 180.0;

      // memory free in a much cleaner way...
      scope (exit) {
	ctx.destroy ();
	ims.destroy ();
	GC.collect();
      }

      ctx.translate (mw/2.0, mh/2.0);
      ctx.rotate (rad);
      ctx.setSourcePixbuf (mpxbf, -mw/2.0, -mh/2.0);
      ctx.paint ();

      //ims.writeToPng ("/tmp/rotated.png");

      if (mpxbf_rotated !is null) { mpxbf_rotated.unref(); }
      mpxbf_rotated = Pixbuf.getFromSurface (ims, 0, 0, 
					     ims.getWidth(), ims.getHeight ());
      get_image_parameters ();
      //count_black_pixels_per_line ();  // <- invoked inside "get_image_parameters"
    }

  }

  /**
   * Detects Skew.
   *
   * Returns:
   *     Skew angle detected in degrees.
   */
  int detect_skew () 
    in { assert (mpxbf !is null); }
    body {

    struct SkewInfo {
      int deg;
      float variance;
    };

    const angle = 10;		// we'll try from -angle..angle , step 1
    float m, v, maxv;
    int ra;			// Rotation angle detected

    SkewInfo[] si;

    // Initial variance...rotation angle is supposed to be 0 deg.
    get_mean_variance_bpixels (m, v);
    si ~= SkewInfo (0, v);
    for (int a = -angle; a <= angle; a += 1) {
      if (a != 0) {

	rotate_by (a);
	get_mean_variance_bpixels (m, v);

	si ~= SkewInfo (a, v);
      }
    }

    // Initial values to compare with
    maxv = -1.0;
    ra = 0;

    foreach ( si_aux ; si) {

      if (si_aux.variance > maxv) {
	maxv = si_aux.variance;
	ra = si_aux.deg;
      }

      writefln ("v: %f , deg: %d , maxv: %f , ra: %d", si_aux.variance, si_aux.deg, maxv , ra);
    }

    return ra;
  }

  /**
   * Create image color map
   */
  void create_color_map () 
    in {
      assert (mh > 0);
      assert (mw > 0);
    }
  body {
    char r,g,b;
    string cname;

    for (int y = 0; y < mh; y++) {
      for (int x = 0; x < mw; x++) {
	get_rgb (x, y, r, g, b);
	
	cname = "";
	cname ~= r;
	cname ~= g;
	cname ~= b;
	mcmap[cname]++;
      }
    }
  }

  /**
   * Get the number of different colours of the image.
   * Returns:
   *    The number of different colours.
   */
  @property ulong get_num_colours () {
    return mcmap.length;
  }

  /**
   * Get the number of Text Lines detected.
   * Returns:
   *    The number of text lines detected.
   */
  @property ulong get_num_textlines () { return mtextlines.length; }

  /**
   * Get the start y-coord of the first pixel of the text line 'l' and
   * the height in pixels of the baseline also.
   * 
   * Parameters:
   *    l = The text line we are interested in.
   *    s = The start y-coord of the base line of the textline.
   *    h = The height in pixels of the baseline
   */
  void get_textline_start_height (in int l, out int s, out int h)
    in { assert ( l < mtextlines.length); }
  body {
    s = mtextlines[l].pixel_start;
    h = mtextlines[l].pixel_height;
  }

  int[] get_textline_skyline (in int l)
    in { assert ( l < mtextlines.length); }
  body {
    return mtextlines[l].skyline;
  }

  int[] get_textline_histogram (in int l)
    in { assert ( l < mtextlines.length); }
  body {
    return mtextlines[l].histogram;
  }

  /**
   * Tries to detect the number of text lines in the image.  It also
   * stores the begining pixel of the text line and its height in
   * pixels.
   */
  void detect_text_lines ()
    in {
      assert (mh > 0);
    }
  body {
    alias to_str = to!string;

    ulong  maxd  = 0;
    ulong  curd  = 0;           // digits of the number of blackpixels
				// of the current line
    int    l     = 0;	        // current line of pixels being processed: 0..mh
    bool   must_exit = false;	// Are al pixel-lines processed?
    float  m,v;
    int    ph    = 0;		// Pixel height of current text line
    int    ipxl  = 0;		// Initial y-coord in pixels of the current text line
    TextLineInfo[] tl;

    mtextlines.length = 0;	// Clear the previous TextLineInfo data

    get_mean_variance_bpixels (m, v); // Mean of black pixels per line
    maxd = to_str(cast(int) m).length; // How many digits does have the mean of black pixels?

    debug writefln ("Max bpx: %s , mean bpx: %s , maxd: %s", 
		    bpx_in_blackest_line, m, maxd);

    // number of digits of the figure of black pixels of the current
    // line (l)
    curd = to_str(get_black_pixels_in_line (l++)).length;

    do {
      // Going up in black pixels
      while ((curd < maxd) && (!must_exit)) {
	if (l >= mh) must_exit = true;
	else curd = to_str(get_black_pixels_in_line (l++)).length;
      }

      ph = 1;
      ipxl = l;
      // Same number == maxd of black pixels
      while ((curd == maxd) && (!must_exit)) {
	if (l >= mh) must_exit = true;
	else {
	  ph++;
	  curd = to_str(get_black_pixels_in_line (l++)).length;
	}
      }
      tl ~= TextLineInfo(ipxl, ph);

    } while (!must_exit);

    int sh = 0;			// Sum of heights
    for (auto i = 0; i < tl.length; i++) {
      sh += tl[i].pixel_height;
    }

    float phmean = cast(float)(sh) / tl.length;	// Pixel height mean
						// for every possible
						// TextLine.

    // We now filter out the TextLines that aren't according to
    // the phmean.
    auto min_pxheight = phmean / 2.0;
    for (auto i = 0; i < tl.length; i++) {
      if ( abs (tl[i].pixel_height - phmean) < min_pxheight )
	mtextlines ~= tl[i];
    }

    // The SkyLine + Histogram for every text line detected
    for (auto i = 0; i < mtextlines.length; i++) {
      build_skyline (mtextlines[i]);
      build_histogram (mtextlines[i]);
    }

    // Detect the x-coords for the right and left margins.
    detect_margins ();
  }

private:

  /////////////////////
  // Class invariant //
  /////////////////////
  invariant () {
    if (mpxbf is null)
      assert (mbase is null);
  }

  void init_instance_variables () {
      mlwmbp = -1;
      mbppl = null;
      mpxbf_rotated = null;
      mpxbf = null;
      mbase = null;
      mnc   = 0;
      mw    = 0;
      mh    = 0;
      mrs   = 0;
      mtextlines = null;
      mrmargin = -1;
      mlmargin = -1;
  }

  /**
   * Locate the x-coordinate for the right/left margins of the text lines.
   */
  void detect_margins () 
    in
      {
	assert (mtextlines !is null);
      }
  body
    {
      int pcount; 		// White/Black pixels count
      int s, h;
      float delta;
      char r,g,b;
      const Color cl = Color.BLACK;

      mlmargin = mw;		// We want the minimum x whose
				// pixel@x,y is black
      mrmargin = 0;		// We want the maximum x whose
				// pixel@x,y is black

      ////////////////////////
      // For every textline //
      ////////////////////////
      for (auto l = 0; l < mtextlines.length; l++)
	{
	  get_textline_start_height (l, s, h);
	  delta = h / 2.0;

	  int pxi = cast (int) (s - delta);
	  int pxf = cast (int) (s + h + delta);

	  pcount += pxf-pxi+1;

	  for (int y = pxi; y <= pxf; y++)
	    {
	      // left margin
	      for (int x = 0; x < mw; x++) {
		get_rgb (x, y, r, g, b);
		if (r == cl && g == cl && b == cl) {
		  if ( (x < mlmargin) && 
		       (!is_pixel_alone (x, y, pxi, pxf)) )
		    {
		      mlmargin = x;
		      break;
		    }
		}
	      }

	      // right margin
	      for (int x = mw-1; x >= 0; x--) {
		get_rgb (x, y, r, g, b);
		if (r == cl && g == cl && b == cl) {
		  if ( (x > mrmargin) && 
		       (!is_pixel_alone (x, y, pxi, pxf)) )
		    {
		      mrmargin = x;
		      break;
		    }
		}
	      }

	    }
	}
      debug writefln ("> lmargin: %d , rmargin: %d", mlmargin, mrmargin);
      debug writefln ("> Total vertical px count: %d", pcount);
    }

  /**
   * We are interested in knowing if pixel@(x,y) is alone -a kind of island-.
   * yb and ye are the initial and final y-coords of a textline.
   * So we check vertically from (x, yb..y..ye) and count black pixels in that pixel line.
   *
   * Returns:
   *   true if the count of black pixels is less than the half of pixels in that line.
   */
  bool is_pixel_alone (in int x, in int y, in int yb, in int ye) 
    in { 
      assert (x < mw);
      assert (y < mh);
    }
  body {
    char r,g,b;
    const Color clb = Color.BLACK;
    int x1, y1, x2, y2;
    int bpc = 0; 		// Black pixel count
    int half = (ye-yb+1)/2;	// (total pix. count)/2

    for (int ly = yb; ly < ye; ly++) {
      get_rgb (x, ly, r, g, b);
      if (r == clb && g == clb && b == clb) {
	bpc++;
      }
    }

    debug writefln ("x: %d, y: %d, half:%d , bpc:%d , alone: %s", x, y, half, bpc, bpc<half);

    // 
    return (bpc < half);
  }

  /**
   * Builds the skyline of a text line.
   * 
   * It stores the y-coord of the highest pixel for the current
   * x-coord in the 'tl' TextLineInfo.
   *
   * Parameters:
   *    tl = The TextLineInfo tho build the Skyline for.
   */
  void build_skyline (ref TextLineInfo tl) {
    char r,g,b;
    const Color cl = Color.BLACK;

    tl.skyline = new int[mw];
    //debug writefln ("Building SkyLine PTR: %x", tl.skyline.ptr);

    for (int x = 0; x < mw; x++) {

      with (tl) {		// Sweet Pascal memories...

	int d = pixel_height / 2;
	int finish = pixel_start + pixel_height + d;

	//skyline[x] = pixel_start-d;
	skyline[x] = finish;

	for (int y = pixel_start-d; y < finish; y++) {
	  get_rgb (x, y, r, g, b);
	  if (r == cl && g == cl && b == cl) {
	    skyline[x] = y;
	    break;
	  }
	}
	/*debug writefln ("Building SkyLine[PS: %d, PH:%d] for x: %d gives y: %d.",
	  pixel_start, pixel_height, x, skyline[x]);*/
      }
    }
  }

  /**
   * Builds the histogram of a text line.
   * 
   * It stores the sum of black pixels for the current
   * x-coord in the 'tl' TextLineInfo.
   *
   * Parameters:
   *    tl = The TextLineInfo tho build the Histogram for.
   */
  void build_histogram (ref TextLineInfo tl) {
    char r,g,b;
    const Color cl = Color.BLACK;

    tl.histogram = new int[mw];
    //debug writefln ("Building SkyLine PTR: %x", tl.skyline.ptr);

    for (int x = 0; x < mw; x++) {

      with (tl) {		// Sweet Pascal memories...

	int d = pixel_height / 2;
	int finish = pixel_start + pixel_height + d;

	histogram[x] = 0;	// Not necessary in D

	for (int y = pixel_start-d; y < finish; y++) {
	  get_rgb (x, y, r, g, b);
	  if (r == cl && g == cl && b == cl) {
	    histogram[x]++;
	  }
	}
	/*debug writefln ("Building SkyLine[PS: %d, PH:%d] for x: %d gives y: %d.",
	  pixel_start, pixel_height, x, skyline[x]);*/
      }
    }
  }

  /**
   * Counts and caches black pixels per line.
   */
  void count_black_pixels_per_line () 
    in { 
      assert (mh > 0); 
      assert (mw > 0); 
    }
  body {
    char  r,g,b;
    Color cl = Color.BLACK;
    int   mbp = -1;

    mbppl = new int[mh];

    for (int y = 0; y < mh; y++) {
      for (int x = 0; x < mw; x++) {
	get_rgb (x, y, r, g, b);
	if (r == cl && g == cl && b == cl)
	  ++mbppl[y];
      }

      if (mbppl[y] > mbp) {
	mbp = mbppl[y];
	mlwmbp = y;
      }
    }
  }

  /**
   * Caches the Pixbuf metadata.
   */
  void get_image_parameters () 
    in { assert (mpxbf !is null); }
  body {
      mbase = mpxbf_rotated.getPixels ();
      mnc   = mpxbf_rotated.getNChannels ();
      mw    = mpxbf_rotated.getWidth ();
      mh    = mpxbf_rotated.getHeight ();
      mrs   = mpxbf_rotated.getRowstride ();

      // Loading image is 25%
      signal_progress.emit ("Counting black-pixels", 0.5);
      count_black_pixels_per_line ();
      signal_progress.emit ("Creating color-map", 0.75);
      create_color_map ();
      signal_progress.emit ("Detecting text-lines", 1.00);
      detect_text_lines ();

      // Clear the progress
      signal_progress.emit ("", 0.00);
  }
  
  //////////
  // Data //
  /////////////////////////////////////////////////////////////////////////

  /**
   * This structure holds information of the text lines detected from
   * the bitmap image.
   */
  struct TextLineInfo {
    /**
     * The Y-coordinate of the pixel tha reflects the text line
     * begining.
     */
    int pixel_start;
    /**
     * The height in pixels of the 'core' of the text line, that is,
     * it does not inlcude upper and lower rectangles that hold
     * 'htqg...' chars.
     */
    int pixel_height;

    /**
     * The SkyLine of the text line.
     */
    int[] skyline;

    /**
     * The Histogram of the text line.
     */
    int[] histogram;
  }
  
  Pixbuf         mpxbf;
  Pixbuf         mpxbf_rotated;
  char*          mbase;
  int            mnc;
  int            mw ;
  int            mh ;
  int            mrs;
  int[]          mbppl;		// Black Pixels Per Line
  int            mlwmbp;	// Line with most black pixels
  int[string]    mcmap;		// Color map of the image
  TextLineInfo[] mtextlines;	// Detected text lines in bitmap, pixel start and pixel height
  int            mrmargin;	// X-coord for the right margin.
  int            mlmargin;	// X-coord for the left margin.
}

////////////////////////////////////////////////////////////////////////////////
// Unit Testing //
//////////////////

/+
unittest {
  Image i = new Image;

  writeln ("\n--- 1st round tests ---");

  assert (i.data   is null);
  assert (!i.is_valid);
  assert (i.width  == -1);
  assert (i.height == -1);

  // hard coded path for now...
  i.load_from_file ("../../data/318982rp10.png");
  assert (i.width  != -1);
  assert (i.height != -1);
  assert (i.count_color_pixels (Image.Color.WHITE) >= 0);
  assert (i.count_color_pixels (Image.Color.BLACK) >= 0);

  /*
  float m, v;
  int l;
  i.get_mean_variance_bpixels (m, v);
  writefln ("Max blk pixels: %d , Mean bpx: %f , Variance bpx: %f", i.get_max_black_pixels_line (l), m, v);

  writefln ("Detected Skew for +10deg is: %d degrees.", i.detect_skew ());
  */

  i.load_from_file ("../../data/318982rm5.png");
  writefln ("Detected Skew for -5deg is: %d degrees.", i.detect_skew ());
  i.rotate_by (10);

  char r,g,b;
  i.get_rgb (130, 534, r, g, b);
  string s;

  s ~= r; s ~= g; s ~= b;
  writefln ("Color name: ·[%d_%d_%d]· - [%s]", r,g,b, s);

  writefln ("Image has %d different colours.", i.get_num_colours);

  foreach (color, times; i.mcmap) {
    writefln ("Color [%s] repeats [%d] times.", 
	      color, times);
  }

  foreach ( color ; i.mcmap.byKey ) {
    writefln ("Color [%s] repeats [%d] times.", 
	      color, i.mcmap[color]);
  }

  writeln ("\n--- 1st round tests ---\n");

}
+/

unittest {
  Image i = new Image;

  writeln ("\n--- 2nd round tests ---");

  assert (i.data   is null);
  assert (!i.is_valid);
  assert (i.width  == -1);
  assert (i.height == -1);

  // hard coded path for now...
  i.load_from_file ("../../data/318982.tif");
  assert (i.is_valid);
  assert (i.height != -1);

  // for (int l = 0; l < i.height; l++) {
  //   writefln ("%d : %d", l, i.get_black_pixels_in_line (l));
  // }

  writefln ("\n\tLine %d has %d blackpixels.", 
	    i.blackest_line, i.bpx_in_blackest_line);

  writefln ("\tNumber %d has %d digits.\n", 
	    i.bpx_in_blackest_line, to!string(i.bpx_in_blackest_line).length );

  writeln ("· Counting lines...");
  writefln ("This image has [%d] lines... I think :/", i.get_num_textlines);

  writefln ("The left/right margins are at X:[%d] , X:[%d]", i.left_margin, i.right_margin);

  writeln ("\n--- 2nd round tests ---\n");

}
