/* -*- Mode: C++; indent-tabs-mode: nil; c-basic-offset: 2 -*- */

/* gtkmm example Copyright (C) 2007 gtkmm development team
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2
 * as published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
 */

#include <gtkmm/main.h>
#include "examplewindow.h"

int main(int argc, char *argv[])
{
  Gtk::Main kit(argc, argv);

  ExampleWindow window;
  //Shows the window and returns when it is closed.
  Gtk::Main::run(window);

  return 0;
}
