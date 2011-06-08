//-*-C++-*-
// Author: Michael S. Summers (ORNL)
/** \ingroup JsonParser */
/*@{*/

/*! \file TypesMixin.h  
 *
 *  
 *
 */

#ifndef  JsonParser_TypesMixin_H
#define  JsonParser_TypesMixin_H

namespace JsonParser {
  
  class TypesMixin {

    typedef enum {
      JSON_T_NONE = 0,
      JSON_T_ARRAY_BEGIN,
      JSON_T_ARRAY_END,
      JSON_T_OBJECT_BEGIN,
      JSON_T_OBJECT_END,
      JSON_T_INTEGER,
      JSON_T_FLOAT,
      JSON_T_NULL,
      JSON_T_TRUE,
      JSON_T_FALSE,
      JSON_T_STRING,
      JSON_T_KEY,
      JSON_T_MAX
    } JsonType;
  };

} // end namespace JsonParser


/*@}*/
#endif

