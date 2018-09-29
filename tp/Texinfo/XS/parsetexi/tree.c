/* Copyright 2010, 2011, 2012, 2013, 2014, 2015
   Free Software Foundation, Inc.

   This program is free software: you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation, either version 3 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program.  If not, see <http://www.gnu.org/licenses/>. */

#include <stdlib.h>
#include <string.h>

#include "tree_types.h"
#include "tree.h"

//int element_counter;

ELEMENT *
new_element (enum element_type type)
{
  ELEMENT *e = malloc (sizeof (ELEMENT));

  //element_counter++;

  /* Zero all elements */
  memset (e, 0, sizeof (*e));

  e->type = type;
  e->cmd = CM_NONE;
  e->args.list = 0;
  e->args.space = 0;
  e->args.number = 0;
  e->contents.list = 0;
  e->contents.space = 0;
  e->contents.number = 0;
  e->parent = 0;
  e->extra = 0;

  return e;
}

void
free_node_contents (ELEMENT *e)
{
  int i;
  if (e)
    {
      for (i = 0; i < e->contents.number; i++)
        {
          if (e->contents.list[i]->parent_type
              == route_not_in_tree)
            destroy_element (e->contents.list[i]);
        }
      free (e);
    }
}

void
destroy_element (ELEMENT *e)
{
  int i;
  free (e->text.text);

  /* Note the pointers in these lists are not themselves freed. */
  free (e->contents.list);
  free (e->args.list);

  for (i = 0; i < e->extra_number; i++)
    {
      switch (e->extra[i].type)
        {
        case extra_string:
        case extra_index_entry:
          free (e->extra[i].value);
          break;
        case extra_element_oot:
          destroy_element_and_children (e->extra[i].value);
          break;
        case extra_element_contents:
          if (e->extra[i].value)
            destroy_element ((ELEMENT *) e->extra[i].value);
          break;
        case extra_element_contents_array:
          {
            int j;
            ELEMENT *array = e->extra[i].value;
            for (j = 0 ; j < array->contents.number; j++)
              {
                if (array->contents.list[j])
                  destroy_element (array->contents.list[j]);
              }
            destroy_element (array);
          break;
          }
        case extra_node_spec:
            {
              NODE_SPEC_EXTRA *nse = (NODE_SPEC_EXTRA *) e->extra[i].value;

              free_node_contents (nse->manual_content);
              free_node_contents (nse->node_content);
              free (nse);
              break;
            }
        case extra_float_type:
          {
            EXTRA_FLOAT_TYPE *eft = (EXTRA_FLOAT_TYPE *) e->extra[i].value;
            free (eft->normalized);

            free (eft);
            break;
          }
        case extra_misc_args:
          //destroy_element_and_children (e->extra[i].value);
            /* Big problem here.  If we call free_node_contents to look for
               'route_not_in_tree' elements, the elements that *were* in
               the tree may have already been freed via reset_parser.
               Also a potential problem for extra_node_spec above.  The best 
               solution would seem to get rid of the need for any 
               'route_not_in_tree' elements. */

          break;
        case extra_def_info:
          free (e->extra[i].value);
          break;

        default:
          break;
        }
    }
  free (e->extra);

  free (e);
}

/* Recursively destroy this element and all data in its descendants. */
void
destroy_element_and_children (ELEMENT *e)
{
  int i;

  for (i = 0; i < e->contents.number; i++)
    destroy_element_and_children (e->contents.list[i]);
  for (i = 0; i < e->args.number; i++)
    destroy_element_and_children (e->args.list[i]);

  destroy_element (e);
}

/* Make sure there is space for at least one more element. */
static void
reallocate_list (ELEMENT_LIST *list)
{
  if (list->number + 1 >= list->space)
    {
      list->space += 10;
      list->list = realloc (list->list, list->space * sizeof (ELEMENT *));
      if (!list->list)
        abort (); /* Out of memory. */
    }
}

void
add_to_element_contents (ELEMENT *parent, ELEMENT *e)
{
  ELEMENT_LIST *list = &parent->contents;
  reallocate_list (list);

  list->list[list->number++] = e;
  e->parent = parent;
}

/* Special purpose function for when we are only using PARENT as an
   array, and we don't want to overwrite E->parent. */
void
add_to_contents_as_array (ELEMENT *parent, ELEMENT *e)
{
  ELEMENT_LIST *list = &parent->contents;
  reallocate_list (list);

  list->list[list->number++] = e;
}

void
add_to_element_args (ELEMENT *parent, ELEMENT *e)
{
  ELEMENT_LIST *list = &parent->args;
  reallocate_list (list);

  list->list[list->number++] = e;
  e->parent = parent;
}

/* Add the element E into the contents of PARENT at index WHERE. */
void
insert_into_contents (ELEMENT *parent, ELEMENT *e, int where)
{
  ELEMENT_LIST *list = &parent->contents;
  reallocate_list (list);

  if (where < 0)
    where = list->number + where;

  if (where < 0 || where > list->number)
    abort ();

  memmove (&list->list[where + 1], &list->list[where],
           (list->number - where) * sizeof (ELEMENT *));
  list->list[where] = e;
  e->parent = parent;
  list->number++;
}

/* Add the element E into the arguments of PARENT at index WHERE. */
void
insert_into_args (ELEMENT *parent, ELEMENT *e, int where)
{
  ELEMENT_LIST *list = &parent->args;
  reallocate_list (list);

  if (where < 0)
    where = list->number + where;

  if (where < 0 || where > list->number)
    abort ();

  memmove (&list->list[where + 1], &list->list[where],
           (list->number - where) * sizeof (ELEMENT *));
  list->list[where] = e;
  e->parent = parent;
  list->number++;
}

ELEMENT *
remove_from_contents (ELEMENT *parent, int where)
{
  ELEMENT_LIST *list = &parent->contents;
  ELEMENT *removed;

  if (where < 0)
    where = list->number + where;

  if (where < 0 || where > list->number)
    abort ();

  removed = list->list[where];
  memmove (&list->list[where], &list->list[where + 1],
           (list->number - (where+1)) * sizeof (ELEMENT *));
  list->number--;
  return removed;
}


ELEMENT *
pop_element_from_args (ELEMENT *parent)
{
  ELEMENT_LIST *list = &parent->args;

  return list->list[--list->number];
}

ELEMENT *
pop_element_from_contents (ELEMENT *parent)
{
  ELEMENT_LIST *list = &parent->contents;

  return list->list[--list->number];
}

ELEMENT *
last_args_child (ELEMENT *current)
{
  if (current->args.number == 0)
    return 0;

  return current->args.list[current->args.number - 1];
}

ELEMENT *
last_contents_child (ELEMENT *current)
{
  if (current->contents.number == 0)
    return 0;

  return current->contents.list[current->contents.number - 1];
}

ELEMENT *
contents_child_by_index (ELEMENT *e, int index)
{
  if (index < 0)
    index = e->contents.number + index;

  if (index < 0 || index >= e->contents.number)
    return 0;

  return e->contents.list[index];
}

ELEMENT *
args_child_by_index (ELEMENT *e, int index)
{
  if (index < 0)
    index = e->args.number + index;

  if (index < 0 || index >= e->args.number)
    return 0;

  return e->args.list[index];
}
