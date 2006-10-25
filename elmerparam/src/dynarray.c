/*

  ElmerParam - A simple system for parametrized computing
 
  Copyright (C) 2006  CSC - Scientific Computing Ltd.

  Authors: Erik Edelmann <Erik.Edelmann@csc.fi>
           Peter R�back <Peter.Raback@csc.fi>
  Address: CSC - Scientific Computing Ltd.
           Keilaranta 14
           02101 Espoo, Finland
            
  This program is free software; you can redistribute it and/or
  modify it under the terms of the GNU General Public License
  as published by the Free Software Foundation; either version 2
  of the License, or (at your option) any later version.
  
  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.
 
  You should have received a copy of the GNU General Public License
  along with this program (in file elmerparam/COPYING); if not, write to
  the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor, 
  Boston, MA 02110-1301, USA.

 */
#include <stdlib.h>
#include <assert.h>
#include "dynarray.h"

/* Set the i:th value of 'da' to 'val'.  If 'da' is NULL, a new
   dynarray_t will be created and returned. */

dynarray_t *dynarray_set(dynarray_t *da, int i, da_numeric_t val)
{
    assert(i >= 0);

    if (!da) {
        da = malloc(sizeof(dynarray_t));
        da->next = NULL;
	da->n = 0;
    }

    if (i+1 > da->n)  da->n = i+1;

    if (i >= DYNARRAY_ALEN)
        da->next = dynarray_set(da->next, i-DYNARRAY_ALEN, val);
    else
        da->a[i] = val;

    return da;
}


/* Get the value of the i:th element of 'da'.  If that element hasn't been
 * assigned to (using da_seti), it's value will be undefined.  */

da_numeric_t dynarray_get(dynarray_t *da, int i)
{
    assert(i >= 0);

    if (!da) {
        da_numeric_t v;
        return v;
    }

    if (i >= DYNARRAY_ALEN)
        return dynarray_get(da->next, i-DYNARRAY_ALEN);
    else
        return da->a[i];
}


void dynarray_kill(dynarray_t *da)
{
    if (!da) return;

    da_kill(da->next);
    free(da);
}
