#!/bin/env ruby
# encoding: utf-8
module EatWhatPattern

  SPACE_EXP = /[\s　]+/u
  UN_SYMBOL_EXP = /[^\s\d\[\]\\\/~`|\[\]{}"':;?.,<>=+\-_\(\)*&^%$#\@!~`‵～！＠＃＄％︿＆＊（）＿－＋＝｜＼｛｝［］；：’＂，．／＜＞？]*/u

  ASK_EAT_WHAT = [/吃(什麼|啥)(?:好|呢|好呢)?[\?？]?/u, /吃[\?？]/u]

  NORMAL_OP_ADD = /\/opadd((?:[\s　]+\S+)*)/u
  SAY_OP_ADD = NORMAL_OP_ADD

  NORMAL_OP_KILL = /\/opkill((?:[\s　]+\S+)*)/u
  SAY_OP_KILL = NORMAL_OP_KILL

  LIKE_FOOD_ADD = /吃到?((?:\s*\S+)+)/u
  WISH_FOOD_ADD = HOPE_FOOD_ADD = WANT_FOOD_ADD = WONDER_FOOD_ADD = LIKE_FOOD_ADD

  NORMAL_OHIYO = /早(?:安(?:好)?)?(?:~|～)?/u

end
