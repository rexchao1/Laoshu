# Gloss review

Checkpoint 8 decision D6a. Every gloss in `data/glosses.tsv` was written by one
model pass and checked by a second, independent pass that saw the proposed gloss
and answered only whether it names a real and primary meaning of that word at
that level. This file records what the second pass rejected, what was done about
each rejection, and a stratified random sample of glosses the two passes agreed
on, read in full because two passes agreeing on a wrong gloss leaves no trace.

## Counts

- Words glossed: 5400
- Disagreements raised by the verification pass: 1
- Disagreements where the gloss was rewritten by hand: 1
- Glosses written by hand from the start, under D6b: 12
- Glosses that fell back to the cleaned CC-CEDICT definition: 0
- Agreed glosses sampled and read in full: 100
- Sampled glosses failing that read: 0

## What this proves and what it does not

The verification pass rejected 1 gloss in 5,400. A rejection rate that low is
weak evidence on its own: it is equally consistent with a good gloss set and
with a second pass that agreed too easily. Decision D6 says so and is why the
sample below exists. The sample is the stronger of the two checks here, and
the honest summary is that the sample found no errors rather than that the
verification pass found almost none.

What the sample did show is that the generation pass handled the cases
decision D5 said no rule could: it took "expensive" for the word CC-CEDICT
leads with a province name, "book" for the one it leads with a classic
abbreviation, and skipped the surname sense on both words that carry one.

## Written by hand from the start

These twelve carry a CC-CEDICT entry with no English in it at all, only a
cross-reference, so the generation pass had nothing to read and the verification
pass had nothing to check against. They are written from the meaning of the
word each entry points at, and the verification pass judged them on meaning
alone. See decision D6b.

| word_index | word | gloss |
| --- | --- | --- |
| 75 | 好玩儿 | fun; amusing |
| 127 | 面条儿 | noodles |
| 261 | 一点儿 | a little; a bit |
| 461 | 小孩儿 | child; kid |
| 756 | 聊天儿 | to chat |
| 924 | 一块儿 | together; in one place |
| 1070 | 差点儿 | almost; nearly |
| 1234 | 干活儿 | to do manual work |
| 1732 | 体检 | medical check-up |
| 2542 | 纪录 | a record |
| 3850 | 大伙儿 | everybody; all of us |
| 5014 | 下功夫 | to put in hard work |

## Disagreements

| word_index | word | level | proposed | the check said | what was done |
| --- | --- | --- | --- | --- | --- |
| 2715 | 脸色 | 5 | facial expression | Means complexion or mood shown on face, not facial expression, a different word | rewritten to "complexion; look on one's face" |

## Sample of agreed glosses

| word_index | word | level | gloss | verdict |
| --- | --- | --- | --- | --- |
| 16 | 菜 | 1 | vegetable; a dish of food | pass |
| 23 | 穿 | 1 | to wear; to put on | pass |
| 44 | 对 | 1 | right; towards | pass |
| 65 | 贵 | 1 | expensive | pass, took "expensive" over the province sense CC-CEDICT leads with |
| 71 | 好 | 1 | good; fine | pass |
| 99 | 看 | 1 | to look at; to watch | pass |
| 108 | 了 | 1 | particle marking a completed action | pass |
| 117 | 卖 | 1 | to sell | pass |
| 127 | 面条儿 | 1 | noodles | pass |
| 190 | 书 | 1 | book | pass, took "book" over the classic abbreviation CC-CEDICT leads with |
| 193 | 水果 | 1 | fruit | pass |
| 200 | 他 | 1 | he; him | pass |
| 206 | 太 | 1 | too; extremely | pass |
| 233 | 想 | 1 | to want; to miss (someone) | pass |
| 236 | 小时 | 1 | hour | pass |
| 250 | 学校 | 1 | school | pass |
| 260 | 椅子 | 1 | chair | pass |
| 306 | 帮忙 | 2 | to help; to do a favor | pass |
| 323 | 次 | 2 | classifier for occurrences; time(s) | pass |
| 330 | 但 | 2 | but | pass |
| 350 | 过去1 | 2 | to go past; to pass by | pass |
| 360 | 坏 | 2 | bad; broken | pass |
| 369 | 介绍 | 2 | to introduce | pass |
| 398 | 没意思 | 2 | boring | pass |
| 404 | 名 | 2 | name; classifier for people | pass |
| 405 | 拿 | 2 | to hold; to take | pass, took "to hold" over the "old variant of" line CC-CEDICT leads with |
| 422 | 让 | 2 | to let; to have someone do something | pass |
| 425 | 上来 | 2 | to come up | pass |
| 427 | 上去 | 2 | to go up | pass |
| 434 | 手表 | 2 | wristwatch | pass |
| 447 | 外面 | 2 | outside | pass |
| 480 | 有时 | 2 | sometimes | pass |
| 486 | 站1 | 2 | station; stop | pass |
| 495 | 走 | 2 | to walk; to leave | pass |
| 530 | 表演 | 3 | to perform; performance | pass |
| 533 | 宾馆 | 3 | hotel | pass |
| 545 | 菜单 | 3 | menu | pass |
| 550 | 查 | 3 | to look up; to check | pass |
| 556 | 常用 | 3 | commonly used | pass |
| 621 | 方法 | 3 | method; way | pass |
| 633 | 附近 | 3 | nearby; in the vicinity | pass |
| 674 | 护照 | 3 | passport | pass |
| 694 | 季节 | 3 | season | pass |
| 698 | 检查 | 3 | to examine; to inspect | pass |
| 755 | 聊 | 3 | to chat | pass |
| 818 | 容易 | 3 | easy | pass |
| 839 | 瘦 | 3 | thin; skinny | pass |
| 840 | 受到 | 3 | to receive; to be subjected to | pass |
| 854 | 体育馆 | 3 | gym; stadium | pass |
| 917 | 牙刷 | 3 | toothbrush | pass |
| 925 | 一样 | 3 | the same; alike | pass |
| 1039 | 并 | 4 | and; also; (not) at all | pass |
| 1066 | 厕所 | 4 | toilet; restroom | pass |
| 1146 | 登机 | 4 | to board a plane | pass |
| 1152 | 低于 | 4 | to be lower than | pass |
| 1199 | 费 | 4 | fee; to cost | pass, skipped the surname sense CC-CEDICT leads with |
| 1213 | 复印 | 4 | to photocopy | pass |
| 1501 | 美好 | 4 | beautiful; wonderful | pass |
| 1530 | 内心 | 4 | inner heart; innermost feelings | pass |
| 1553 | 皮鞋 | 4 | leather shoes | pass |
| 1596 | 取得 | 4 | to obtain; to achieve | pass |
| 1622 | 入 | 4 | to enter; to join | pass |
| 1666 | 使 | 4 | to make; to cause | pass |
| 1719 | 谈 | 4 | to talk; to chat | pass, skipped the surname sense CC-CEDICT leads with |
| 1828 | 性 | 4 | nature; suffix -ness/-ity | pass |
| 1924 | 着 | 4 | to fall asleep; to catch fire | pass, pass, marginal: both senses are real and common, neither is clearly first |
| 1926 | 者 | 4 | particle meaning 'the one who' or '-er' | pass |
| 1969 | 专业 | 4 | major; specialty; professional | pass |
| 2200 | 从不 | 5 | never | pass |
| 2277 | 点赞 | 5 | to like (on social media) | pass |
| 2325 | 罚款 | 5 | fine (penalty); to fine | pass |
| 2586 | 降水 | 5 | precipitation (rain or snow) | pass, noun gloss against a verb tag, and the word is a noun |
| 2732 | 流传 | 5 | to spread; to circulate | pass |
| 2874 | 抢 | 5 | to grab; to rob | pass |
| 2913 | 热爱 | 5 | to love deeply | pass |
| 2936 | 如同 | 5 | like; as | pass |
| 3091 | 随手 | 5 | in passing; without extra trouble | pass |
| 3143 | 同一 | 5 | the same; identical | pass |
| 3187 | 违反 | 5 | to violate (a law, rule) | pass |
| 3198 | 位置 | 5 | position; place; location | pass |
| 3233 | 闲 | 5 | idle; free; at leisure | pass, three near-synonyms read as one meaning |
| 3415 | 幼儿园 | 5 | kindergarten | pass |
| 3494 | 政府 | 5 | government | pass |
| 3567 | 资格 | 5 | qualifications | pass |
| 3908 | 顶 | 6 | top; classifier for hats | pass |
| 4005 | 辅导 | 6 | to tutor; to coach | pass |
| 4183 | 灰尘 | 6 | dust | pass |
| 4233 | 家居 | 6 | home; residence | pass |
| 4243 | 坚定 | 6 | firm; resolute | pass |
| 4329 | 镜头 | 6 | camera lens; shot | pass |
| 4332 | 酒精 | 6 | alcohol (ethanol) | pass |
| 4614 | 期限 | 6 | deadline; time limit | pass |
| 4632 | 牵 | 6 | to lead (by hand or rope) | pass |
| 4645 | 瞧 | 6 | to look; to take a look | pass |
| 4683 | 缺陷 | 6 | defect; flaw | pass |
| 4878 | 特定 | 6 | specific; particular | pass |
| 4919 | 投票 | 6 | to vote | pass |
| 4946 | 托运 | 6 | to check in (baggage/cargo) | pass |
| 5038 | 相连 | 6 | to be linked; connected | pass |
| 5328 | 中 | 6 | to hit a target; to win | pass |
