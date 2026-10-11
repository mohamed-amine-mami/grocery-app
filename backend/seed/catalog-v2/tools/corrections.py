"""Name-based corrections applied after the sub-category / keyword classification. Each returns (category, rule-id) or None."""
import re
from textlib import fold
RULES = [
 # traditional breakfast / pantry items (Géant files chamia, bsissa and zrir under Épicerie > Petit déjeuner)
 ('C1', r'^(?:bonbons?|dragees?|chocolat)\b', None),  # guard: candies and chocolate that merely contain chamia stay where they are (handled below)
]
def correct(name, cat):
    n = fold(name)
    # --- chamia / bsissa / zrir / tahina review -------------------------------------------------
    if re.search(r'\b(bonbons?|dragees?|sucettes?|chewing)\b', n) and re.search(r'chamia|helva|halwa', n):
        return 'chocolat-confiserie', 'C1 candy filled with chamia stays confectionery'
    if re.search(r'\b(ghrayba|ghraiba|ghribia)\b', n):
        return 'biscuits-gateaux', 'C2 ghrayba is a shortbread biscuit'
    if re.search(r'\btahin[ae]?\b', n) and not re.search(r'chamia|helva|halwa', n):
        return 'epicerie', 'C3 tahini is a pantry sesame paste'
    if re.search(r'\b(pops?)\b', n) and re.search(r'(sesame|datte|noisette|choco)', n) and cat in ('petit-dejeuner', 'chocolat-confiserie', 'epicerie', 'produits-traditionnels'):
        return 'snacks-aperitif', 'C4 sesame/date "pops" are snack bites'
    if re.search(r'\b(chamia|helva|halwa|bsissa|zrir)\b', n) and cat in ('chocolat-confiserie', 'epicerie', 'biscuits-gateaux', 'boulangerie', 'petit-dejeuner'):
        return 'produits-traditionnels', 'C5 traditional Tunisian specialty (chamia/bsissa/zrir): its own food type, neither confectionery nor a generic breakfast item'
    if re.match(r'^(droo|sorgho|assida|mesfouf|zgougou|pate zgougou|pois chiche moulu|mais moulu)\b', n) and cat in ('epicerie', 'petit-dejeuner') and not re.search(r'\b(cake|muffin|preparation|creme dessert|biscuit)\b', n):
        return 'produits-traditionnels', 'C6 traditional flour / grain / paste preparation'
    # --- plain classification mistakes found in review ---------------------------------------------
    if re.search(r'^citrons?\b', n) and cat == 'legumes':
        return 'fruits', 'M1 citron is a fruit'
    if re.search(r'^sardines?\b', n) and cat in ('viandes', 'volaille'):
        return 'poissons-fruits-de-mer', 'M2 sardine is fish'
    if re.search(r'^(soupe|noodles?|pates? noodles?|puree|bouillons?|vermicelle)\b', n) and cat in ('volaille', 'viandes', 'poissons-fruits-de-mer', 'charcuterie-traiteur', 'surgeles'):
        return 'epicerie', 'M3 soup / noodles / stock / mash is a pantry item'
    if re.search(r'^glaces? sandwich\b', n) and cat != 'surgeles':
        return 'surgeles', 'M4 ice-cream sandwich'
    if re.search(r'\bsaucisses?\b', n) and cat in ('viandes', 'volaille'):
        return 'charcuterie-traiteur', 'M5 sausages are charcuterie'
    if re.search(r'^(chips|snacks?)\b', n) and cat == 'boissons':
        return 'snacks-aperitif', 'M6 crisps are not drinks'
    if re.search(r'^(leben|lben|raieb|raib)\b|^l.ben\b', n) and cat != 'produits-laitiers':
        return 'produits-laitiers', 'M7 fermented milk'
    if re.search(r'^fromages?\b', n) and cat in ('produits-laitiers',):
        return 'fromages', 'M8 cheese'
    if re.search(r'^pain\b|^mlewi\b|^croissants?\b|^pains?\b', n) and cat in ('petit-dejeuner', 'biscuits-gateaux', 'snacks-aperitif') and not re.search(r'epice|farine|grille|biscotte', n):
        return 'boulangerie', 'M9 bread / viennoiserie'
    if re.search(r'^boissons?\b', n) and cat == 'petit-dejeuner':
        return 'boissons', 'M10 drink'
    if re.search(r'^gaufrettes?\b', n) and cat == 'produits-laitiers':
        return 'biscuits-gateaux', 'M11 wafer'
    if re.search(r'pan[eé](?:e|s|es)?\b', n) and re.search(r'\b(boulettes?|nuggets?|escalopes?|calamars?|poisson|poulet|dinde|fromage)\b', n) and cat in ('viandes', 'volaille', 'poissons-fruits-de-mer', 'charcuterie-traiteur'):
        return 'surgeles', 'M12 breaded ready-to-fry items are frozen products'
    return None
