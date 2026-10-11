# Sub-category (Géant Drive) -> GrocerGo category. Anything absent is excluded (non-food or out of scope).
GD_MAP = {}
def _m(cat, *subs):
    for s in subs: GD_MAP[s] = cat
_m('fruits','fruits-de-saison','fruits-exotiques')
_m('surgeles','fruits')
_m('legumes','legumes-frais','herbes-aromatiques','salades')
_m('surgeles','legumes','frites','gamme-panee','rotisserie-et-grillade','glaces','glacons-alimentaires-non-alimentaires')
_m('viandes','boeuf','porc','hachees-et-en-morceau')
_m('volaille','volaille','volaille-et-lapin')
_m('poissons-fruits-de-mer','poissons','coquillages-et-crustaces','coquillages-crustaces-et-mollusques','saumons-fumes-boutargues-foie-gras-et-derives')
_m('produits-laitiers','yaourts-natures-et-aromatises','yaourts-a-boire','yaourts-aux-fruits','yaourts-alleges','leben-et-raieb','laits-industriels','laits-aromatises-et-vitamines','laits-demi-ecremes','laits-entiers','laits-ecremes','cremes-fraiches','beurres','margarines','cremes-dessert','boissons-lactees','oeufs-frais','oeufs-frais-omega-3')
_m('fromages','fromages-a-tartiner','fromages-en-portions','fromages-rapes','slices','fromages-de-cuisson','fromages-enfant','fromages-blancs','fromages-ultra-frais')
_m('charcuterie-traiteur','plats-cuisines','plats-cuisines-et-minis-sales','pates-pizzas-et-sales','sandwichs-et-pizzas','salade-mechouia')
_m('boulangerie','pains-et-viennoiseries')
_m('biscuits-gateaux','madeleines-et-cakes','biscuits-a-la-creme','biscuits-secs','gaufrettes','cookies','cigares-et-langues-de-chat','barres-biscuitees','cakes-patisseries-et-gateaux')
_m('chocolat-confiserie','bonbons','chewing-gum-bubble-gum','tablettes-et-barres-de-chocolat','chocolats-fourres')
_m('snacks-aperitif','chips-et-pop-corn','biscuits-aperitifs')
_m('produits-traditionnels','chamia-bsissa-et-zrir','preparations-traditionnelles')
_m('petit-dejeuner','petit-dejeuner','cereales-et-barres-cerealieres','confitures','miels','pates-a-tartiner','biscottes','chocolat-en-poudre')
_m('boissons','cola-et-boissons-gazeuses','pur-jus-de-fruits','nectar-de-fruits','sirops-et-concentres-de-sirop','eaux-plates','eaux-gazeifiees','boissons-energetiques','boissons-instantanees','bieres-sans-alcool','jus-de-fruits-frais','thes-infusions','cafes-solubles','cafes-moulus','cafes-en-capsule','cafes-chicorees')
_m('epicerie','epices','pates-et-chorba','pates-speciales','pates-riz-et-farines','pates-aux-oeufs','pates-fraiches','couscous','riz','farines','farines-et-semoules','aides-a-la-patisserie','desserts-a-preparer','thons-entiers','thons-en-miettes','filets-de-thon','sardines','vinaigrettes-et-sauces-salades','harissa','vinaigres','huiles-d-olive','huiles-vegetales','huiles-vinaigres-et-condiments','legumes-secs','lentilles-et-pois-chiches','haricots','cornichons-olives-et-condiments','mayonnaises','moutardes','ketchup','tomates-concassees','tomates-pelees-cubees','doubles-concentres-de-tomates','sauces-chaudes-a-base-de-tomate','champignons','mais','petits-pois','petits-pois-et-carottes','melanges-de-legumes','fruits-secs','fruits-seches','dattes','sucres-speciaux','sucre-en-poudre','sucres','sucres-en-morceaux','edulcorants','sels','pates-feuilletees','pates-a-pizza-et-pates-brisees','fruits-au-sirop')
# Explicitly out of scope although food-adjacent (reported for review).
GD_EXCLUDED_REVIEW = {'boissons-et-grignotages':'dietary supplements / powders (not grocery staples)','tablettes':'ambiguous (electronic tablets)'}
CATEGORIES = [
 ('fruits','Fruits',None),('legumes','Légumes',None),('viandes','Viandes',None),('volaille','Volaille',None),
 ('poissons-fruits-de-mer','Poissons et fruits de mer',None),('produits-laitiers','Produits laitiers',None),('fromages','Fromages',None),
 ('charcuterie-traiteur','Charcuterie et traiteur',None),('boulangerie','Boulangerie',None),('surgeles','Surgelés',None),
 ('epicerie','Épicerie',None),('produits-traditionnels','Produits traditionnels',None),('petit-dejeuner','Petit déjeuner',None),('biscuits-gateaux','Biscuits et gâteaux',None),
 ('chocolat-confiserie','Chocolat et confiserie',None),('snacks-aperitif','Snacks et apéritif',None),('boissons','Boissons',None),
]
