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
import core.memory: GC;         // We need to play with the garbage collector
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

////////////
// Config //
////////////
import config.types;

//-- Model -----------------------------------------------------------
import model.pixmap;

//-- Utils -----------------------------------------------------------
import utils.statistic;

////////////////
// Code begin //
//////////////////////////////////////////////////////////////////////

/**
 * Class Image: This class represents an image. Normally this image
 * will be a scanned page.
 *
 */
class Image {

  //-- Public part --------------------------------------------------------------

  public
  {

    /////////////////
    // Constructor //
    /////////////////
    this () {
      the_pixmap = new Pixmap;        // The pixmap is alive all the time

      init_instance_variables ();
    }

    /////////////////
    // Destructor  //
    /////////////////
    ~this () {
      //debug writeln ("Destroying Image!");

      the_pixmap.destroy ();
      //the_pixmap = null;

      //debug writeln ("After dstroying the_pixmap!");
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

    @property Pixbuf raw_data () 
    {
      if (the_pixmap is null)
        return null;
      else
        return the_pixmap.get_gdkpixbuf;
    }
    @property Pixmap get_pixmap () { return the_pixmap; }

    @property int width () {
      return the_pixmap.width;
    }

    @property int height () {
      return the_pixmap.height;
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
     *   The X coordinate for the right margin.
     */
    @property int right_margin () { return mrmargin; }


    /// Get the black pixels average
    @property float get_black_pixels_average () { return mbpaverage; }
    /// Get the black pixels variance
    @property float get_black_pixels_variance () { return mbpvariance; }

    /**
     * Counts black pixels in one line.
     *
     * Params:
     *   y = The line to search black pixels in.
     *   
     * Returns:
     *     the number of black pixels in line 'y'.
     */
    uint get_black_pixels_in_line (int y) 
      in {
        assert (the_pixmap.is_valid_pixmap);
        assert (y < the_pixmap.height);
      }
    body {
      return mbppl[y];
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
    
      for (int x = 0; x < the_pixmap.width; x++)
        for (int y = 0; y < the_pixmap.height; y++) {
          get_rgb (x, y, r, g, b);
          if (r == cl && g == cl && b == cl)
            c++;
        }
      return c;
    }
  
    /**
     * Loads the image in filename into the pixbuf.
     */
    void load_from_file (string filename) 
      in {
        assert (the_pixmap !is null);
      }
    body {

      if (filename == "") return;

      signal_progress.emit ("Loading image", 0.25);
      the_pixmap.load_from_file (filename);

      if (the_pixmap.is_valid_pixmap) {
        get_image_parameters ();
      } else {
        init_instance_variables ();
      }
    }

    /**
     * Get the RGB values from pixel x,y,
     */
    void get_rgb (in int x, in int y, out char r, out char g, out char b) {
      the_pixmap.get_rgb (x,y,r,g,b);
    }

    /**
     * Get the composite value as an uint @x,y
     */
    uint get_composite_value (in int x, in int y) {
      return the_pixmap.get_composite_value (x, y);
    }

    /**
     * Set the RGB values for pixel x,y,
     */
    void set_rgb (in int x, in int y, in char r, in char g, in char b) {
      the_pixmap.set_rgb (x,y,r,g,b);
    }

    /**
     * Checks for a valid image loaded.
     */
    @property bool is_valid () {
      if (the_pixmap !is null)
        return the_pixmap.is_valid_pixmap;
      else
        return false;
      //return mpxbf !is null;
    }

    /**
     * Rotate the image by 'deg' degrees.
     * 
     * Params:
     *   deg = The number of degrees to rotate the image.
     */
    void rotate_by (float deg) {

      if (the_pixmap.is_valid_pixmap) {
        the_pixmap.rotate_by (deg);
        get_image_parameters ();
      }
    }

    /**
     * Detects Skew.
     *
     * Returns:
     *     Skew angle detected in degrees.
     */
    int detect_skew ()
      in {
        assert (the_pixmap.is_valid_pixmap);
      }
    body {

      struct SkewInfo {
        int deg;
        float variance;
      }

      const angle = 10;         // we'll try from -angle..angle , step 1
      float m, v, maxv;
      int ra;                   // Rotation angle detected

      SkewInfo[] si;

      // Initial variance...rotation angle is supposed to be 0 deg.
      si ~= SkewInfo (0, mbpvariance);
      for (int a = -angle; a <= angle; a += 1) {
        if (a != 0) {

          rotate_by (a);
          //get_average_variance_bpixels (m, v);

          si ~= SkewInfo (a, mbpvariance);
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

        /*  debug writefln ("v: %f , deg: %d , maxv: %f , ra: %d", 
            si_aux.variance, si_aux.deg, maxv , ra);*/
      }

      return ra;
    }

    /**
     * Create image color map
     */
    void create_color_map () 
      in {
        assert (the_pixmap.is_valid_pixmap);
      }
    body {
      char r,g,b;
      string cname;

      for (int y = 0; y < the_pixmap.height; y++) {
        for (int x = 0; x < the_pixmap.width; x++) {
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
      in {
        assert ( l < mtextlines.length);
      }
    body {
      s = mtextlines[l].pixel_start;
      h = mtextlines[l].pixel_height;
    }

    coord_t[] get_textline_skyline (in int l)
      in {
        assert ( l < mtextlines.length);
      }
    body {
      return mtextlines[l].skyline;
    }

    coord_t[] get_textline_bottomline (in int l)
      in {
        assert ( l < mtextlines.length);
      }
    body {
      return mtextlines[l].bottomline;
    }

    coord_t[] get_textline_histogram (in int l)
      in {
        assert ( l < mtextlines.length);
      }
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
        assert (the_pixmap.is_valid_pixmap);
      }
    body {

      /**
       * Get the fingerprint for pixel line 'line' based on the
       * average and the std.dev.
       */
      double finger_print (coord_t line) {
        return (get_black_pixels_in_line (line) - 
                get_black_pixels_average()) / get_black_pixels_variance.sqrt();
      }

      double  k                = 7;             // Kth part of bpx_fingerprint
      double  stdev            = get_black_pixels_variance.sqrt();
      double  avg              = get_black_pixels_average();
      uint    most_bpx         = bpx_in_blackest_line ();
      double  bpx_fingerprint  = ((most_bpx - avg) / stdev) / k;
      double  line_fingerprint = 0.0;
      coord_t l                = 0; // current line of pixels being processed: 0..mh
      uint    tlc              = 0; // text line count
      bool    in_textline,
	new_position;
      coord_t        ph        = 0;     // Pixel height of current text line
      coord_t        ipxl      = 0; // Initial y-coord in pixels of the current text line

      //writefln ("bpx_fp: %s", bpx_fingerprint);

      mtextlines.length = 0;    // Clear the previous TextLineInfo data

      // Lets position ourselves in the firs text line....more or
      // less...
      l = 0;
      do {
        in_textline = finger_print(l) >= bpx_fingerprint;
        l++;
      } while ((!in_textline) && (l < mbppl.length));

      writefln ("bpx_fp: %s / First txtline starts at %s y-pixel.", bpx_fingerprint, l);

      for ( ; l < mbppl.length; l++) {

        tlc++;

        ph = 1;                 // Pixel height of current line now is 1px
        ipxl = l;               // The initial pixel of current line is 'l'.

        // In a text line...jump it...
        //writeln ("Text Line.");
        do {
          new_position = finger_print(l) >= bpx_fingerprint;
          l++;
          
          ph++;
          
          if (l >= mbppl.length)
            break;
        } while (in_textline == new_position);
        in_textline = new_position;

        mtextlines ~= TextLineInfo(ipxl, ph);

        // Now we are in a white line....let's jump over it!
        //writeln ("White Line.");
        do {
          l++;

          if (l >= mbppl.length)
            break;
          else {
            new_position = finger_print(l) >= bpx_fingerprint;
          }
        } while (in_textline == new_position);
        in_textline = new_position;

        if (l >= mbppl.length)
          break;
        

        /*writefln ("px(%s) fp[%s]: %s (%s)", 
	  mbppl[l], l, finger_print(l), 
	  finger_print(l) >= bpx_fingerprint ? "text line" : "white line");*/
      }

      writefln ("This page has %s text lines.", tlc);

      // The SkyLine + Histogram for every text line detected
      for (auto i = 0; i < mtextlines.length; i++) {
        build_sky_bottom_line (mtextlines[i]);
        build_histogram (mtextlines[i]);
      }
    }

    /**
     * Tries to detect the number of text lines in the image.  It also
     * stores the begining pixel of the text line and its height in
     * pixels.
     */
    void detect_text_lines_old ()
      in {
        assert (the_pixmap.is_valid_pixmap);
      }
    body {
      alias to_str = to!string;

      ulong  maxd      = 0;
      ulong  curd      = 0;     // digits of the number of blackpixels
                                // of the current line
      coord_t    l     = 0; // current line of pixels being processed: 0..mh
      bool   must_exit = false; // Are al pixel-lines processed?
      float  m,v;
      coord_t    ph    = 0;     // Pixel height of current text line
      coord_t    ipxl  = 0; // Initial y-coord in pixels of the current text line
      TextLineInfo[] tl;

      mtextlines.length = 0;    // Clear the previous TextLineInfo data

      //get_average_variance_bpixels (m, v); // Average of black pixels per line
      maxd = to_str(cast(int) mbpaverage).length; // How many digits does have the average of black pixels?

      debug {
        writefln ("*) Detecting text lines. Height is %d", the_pixmap.height);
        writefln ("Max bpx: %s , average bpx: %s , maxd: %s", 
                  bpx_in_blackest_line, mbpaverage, maxd);
      }

      // throw new Exception ("Exit"); // Kind of exit();

      // number of digits of the figure of black pixels of the current
      // line (l)
      curd = to_str(get_black_pixels_in_line (l++)).length;

      do {
        //debug writefln ("Climbing mountain...l=(%d), curd(%d) maxd(%d)", l, curd, maxd);

        // Going up in black pixels
        while ((curd <= maxd) && (!must_exit)) {
          if (l >= the_pixmap.height) must_exit = true;
          else curd = to_str(get_black_pixels_in_line (l++)).length;
        }

        ph = 1;
        ipxl = l;

        //debug writefln ("Up in the mountain...l(%d), curd(%d) maxd(%d)", l, curd, maxd);

        // Same number == maxd of black pixels
        while ((curd >= maxd) && (!must_exit)) {
          if (l >= the_pixmap.height) must_exit = true;
          else {
            ph++;
            curd = to_str(get_black_pixels_in_line (l++)).length;
          }
        }

        tl ~= TextLineInfo(ipxl, ph);

      } while (!must_exit);

      debug writeln ("Adding heights...");

      int sh = 0;                       // Sum of heights
      for (auto i = 0; i < tl.length; i++) {
        sh += tl[i].pixel_height;
      }

      float phaverage = cast(float)(sh) / tl.length;    // Pixel height average
      // for every possible
      // TextLine.

      debug writeln ("Filtering TextLines...");

      // We now filter out the TextLines that aren't according to
      // the phaverage.
      auto min_pxheight = phaverage / 2.0;
      for (auto i = 0; i < tl.length; i++) {
        if ( abs (tl[i].pixel_height - phaverage) < min_pxheight )
          mtextlines ~= tl[i];
      }

      debug writeln ("Building skybot+hist...");

      // The SkyLine + Histogram for every text line detected
      for (auto i = 0; i < mtextlines.length; i++) {
        build_sky_bottom_line (mtextlines[i]);
        build_histogram (mtextlines[i]);
      }

      debug writeln ("Detecting margins...");

      // Detect the x-coords for the right and left margins.
      detect_margins ();
    }
  }

  //-- Private part ------------------------------------------------------------

  private
  {

    /////////////////////
    // Class invariant //
    /////////////////////
    invariant () {
    }

    void init_instance_variables () {
      mlwmbp     = -1;
      mbppl      = null;
      mtextlines = null;
      mrmargin   = -1;
      mlmargin   = -1;
    }

    /**
     * Locate the x-coordinate for the right/left margins of the text lines.
     */
    void detect_margins () 
      in {
        assert (mtextlines !is null);
      }
    body
      {
        int pcount;             // White/Black pixels count
        int s, h;
        float delta;
        char r,g,b;
        const Color cl = Color.BLACK;

        mlmargin = the_pixmap.width; // We want the minimum x whose
        // pixel@x,y is black
        mrmargin = 0;           // We want the maximum x whose
                                // pixel@x,y is black

        ////////////////////////
        // For every textline //
        ////////////////////////
        for (auto l = 0; l < mtextlines.length; l++)
          {
            get_textline_start_height (l, s, h);
            delta = h / 2.0;

            int pxi = min(cast (int) (s - delta), the_pixmap.height);
            int pxf = min(cast (int) (s + h + delta), the_pixmap.height);

            pcount += pxf-pxi+1;

            for (int y = pxi; y <= pxf; y++)
              {
                // left margin
                for (int x = 0; x < the_pixmap.width; x++) {
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
                for (int x = (the_pixmap.width - 1); x >= 0; x--) {
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
        assert (x <= the_pixmap.width, "is_pixel_alone: x-coord overflow.");
        assert (y <= the_pixmap.height, "is_pixel_alone: y-coord overflow.");
      }
    body {
      char r,g,b;
      const Color clb = Color.BLACK;
      int x1, y1, x2, y2;
      int bpc = 0;              // Black pixel count
      int half = (ye-yb+1)/2;   // (total pix. count)/2

      for (int ly = yb; ly < ye; ly++) {
        get_rgb (x, ly, r, g, b);
        if (r == clb && g == clb && b == clb) {
          bpc++;
        }
      }

      // Pixel@(x,y) is almost alone if...
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
    void build_sky_bottom_line (ref TextLineInfo tl) {
      char r,g,b;
      const Color cl = Color.BLACK;

      tl.skyline    = new coord_t[the_pixmap.width];
      tl.bottomline = new coord_t[the_pixmap.width];

      //debug writefln ("Building SkyLine PTR: %x", tl.skyline.ptr);
      //debug writeln  ("*) Building Sky/Bottom lines.");

      for (int x = 0; x < the_pixmap.width; x++) {

        with (tl) {             // Sweet Pascal memories...

          coord_t d = pixel_height / 2;
          coord_t start =  cast (coord_t) (pixel_start - d);
          coord_t finish = cast (coord_t) (pixel_start + pixel_height + d);

          //skyline[x] = pixel_start-d;
          skyline[x] = finish;
          bottomline[x] = start;

          for (coord_t y = start; y < finish; y++) {
            get_rgb (x, y, r, g, b);
            if (r == cl && g == cl && b == cl) {
              skyline[x] = y;
              break;
            }
          }
          for (coord_t y = finish; y > start; y--) {
            get_rgb (x, y, r, g, b);
            if (r == cl && g == cl && b == cl) {
              bottomline[x] = y;
              break;
            }
          }

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

      tl.histogram = new coord_t[the_pixmap.width];
      //debug writefln ("Building SkyLine PTR: %x", tl.skyline.ptr);
      //debug writeln  ("*) Building Histogram lines.");

      for (int x = 0; x < the_pixmap.width; x++) {

        with (tl) {             // Sweet Pascal memories...

          int d = pixel_height / 2;
          int finish = pixel_start + pixel_height + d;

          histogram[x] = 0;     // Not necessary in D

          for (int y = pixel_start-d; y < finish; y++) {
            get_rgb (x, y, r, g, b);
            if (r == cl && g == cl && b == cl) {
              histogram[x]++;
            }
          }
        }
      }
    }

    /**
     * Counts and caches black pixels per line.
     */
    void count_black_pixels_per_line () 
      in {
        assert (the_pixmap.is_valid_pixmap); 
      }
    body {

      mbppl = the_pixmap.get_bppl; // The array with the count of black pixels per line
      mlwmbp = the_pixmap.get_lwmbp; // The line with most black pixels.
      // Calculate the average and the variance of black pixels.
      calculate_average_variance_bpixels ();
    }

    /**
     * Calculates the average and the variance of the black pixels
     * from the Image.
     */
    void calculate_average_variance_bpixels () {
      mbpaverage = mbpvariance = 0.0;
      the_pixmap.calculate_average_variance_bpixels (mbpaverage, mbpvariance);
    }

    /**
     * Caches the Pixbuf metadata.
     */
    void get_image_parameters () 
      in {
        assert (the_pixmap.is_valid_pixmap);
      }
    body {
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
      coord_t pixel_start;
      /**
       * The height in pixels of the 'core' of the text line, that is,
       * it does not include upper and lower rectangles that hold
       * 'htqg...' chars.
       */
      coord_t pixel_height;

      /**
       * The SkyLine of the text line.
       */
      coord_t[] skyline;

      /**
       * The BottomLine of the text line.
       */
      coord_t[] bottomline;

      /**
       * The Histogram of the text line.
       */
      coord_t[] histogram;
    }

    Pixmap         the_pixmap;  // The pixmap abstraction used to hold the scanned page
    uint[]         mbppl;       // Black Pixels Per Line
    float          mbpaverage;  // The black pixels per line average
    float          mbpvariance; // The black pixels per line variance
    int            mlwmbp;      // Line with most black pixels
    int[string]    mcmap;       // Color map of the image
    TextLineInfo[] mtextlines;  // Detected text lines in bitmap, pixel start and pixel height
    int            mrmargin;    // X-coord for the right margin.
    int            mlmargin;    // X-coord for the left margin.
  }
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
 i.get_average_variance_bpixels (m, v);
 writefln ("Max blk pixels: %d , Average bpx: %f , Variance bpx: %f", i.get_max_black_pixels_line (l), m, v);

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

/+unittest {
 Image i = new Image;
 //i.destroy ();

 writeln ("\n--- 2nd round tests ---");

 assert (i.raw_data is null);
 assert (!i.is_valid);
 assert (i.width  == -1);
 assert (i.height == -1);

 // hard coded paths for now...
 // foreach (f ; ["../../data/318982.tif",  "../../data/439040bn.tif",  
 //            "../../data/8048.tif", "../../data/317548.tif"]) 
 foreach (f ; ["../../data/317548.tif"])
 {  
 //i = new Image;
 writeln (" ---------===============------------- ");
 i.load_from_file (f);

 assert (i.is_valid);
 assert (i.height != -1);

 writefln ("Image width: %d height: %d colours: %d", 
 i.width, i.height, i.get_num_colours);

 i.init_instance_variables ();
 }

 /*
 writefln ("\n\tLine %d has %d blackpixels.", 
 i.blackest_line, i.bpx_in_blackest_line);

 writefln ("\tNumber %d has %d digits.\n", 
 i.bpx_in_blackest_line, to!string(i.bpx_in_blackest_line).length );

 writeln ("· Counting lines...");
 writefln ("This image has [%d] lines... I think :/", i.get_num_textlines);

 writefln ("The left/right margins are at X:[%d] , X:[%d]", i.left_margin, i.right_margin);

 writeln ("\n--- 2nd round tests ---\n");
*/
}+/

unittest {
  Image i = new Image;

  writeln ("\n--- Statistic tests ---");

  assert (i.raw_data is null);
  assert (!i.is_valid);
  assert (i.width  == -1);
  assert (i.height == -1);

  // hard coded paths for now...
  // foreach (f ; ["../../data/318982.tif",  "../../data/439040bn.tif",  
  //            "../../data/8048.tif", "../../data/317548.tif"]) 
  foreach (f ; ["../../data/318982.tif","../../data/317548.tif"])
    {  
      //i = new Image;
      writeln (" ---------===============------------- ");
      i.load_from_file (f);

      assert (i.is_valid);
      assert (i.height != -1);

      writefln ("Image width: %d height: %d", i.width, i.height);
      writefln ("·-> old average: %f old stdev: %f", i.mbpaverage, i.mbpvariance.sqrt);
      writefln ("·-> average: %f stdev: %f", i.mbppl.average, i.mbppl.stdev);

      //foreach (v ; i.mbppl) writeln (v);

      writeln ("Suma de pixels en mbppl: ", i.mbppl.sum);
      i.detect_text_lines ();
    }
}
