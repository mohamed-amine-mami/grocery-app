# NOTE: the "reconciliation" block written by this script (net removed/added) was superseded by a record-linked reconciliation applied afterwards (review-round4.md section 2). The cause partition is still valid.
import json,collections
D='/Users/medamine/projects/grocery-app/backend/seed/catalog-v2/'
W='/private/tmp/claude-501/-Users-medamine-projects-grocery-app/1b6c0ba4-129b-4044-802f-b7eb0950f62f/scratchpad/'
ch=json.load(open(D+'changes-since-rev2.json'))
P={p['slug']:p for p in json.load(open(D+'provenance.json'))['products']}
st2=json.load(open(W+'out/stage2.json'))
cfm={r['sid'] for r in st2['cfDecisions'] if r['decision']=='merged'}
pairs=json.load(open(W+'work/pair_merges.json'))
pairids=set()
for x in pairs: pairids|=set(x['a'])|set(x['b'])
bm={(r['source'],r['sid']) for r in st2['brandMergeAudit']}
dm={(b,a2.lower()) for a1,a2,b,_ in st2['descriptorMerges']}
over=collections.Counter(); excl=collections.Counter()
for g in ch['merged']:
    pv=P[g['newSlug']]; c=set()
    if any(s['source']=='carrefour' and s['sourceId'] in cfm for s in pv['sources']): c.add('carrefour-size-from-page')
    if {f"{s['source']}:{s['sourceId']}" for s in pv['sources']}&pairids: c.add('pack-photo-pair')
    if any((pv.get('brand'),m['name'].lower()) in dm for m in g['mergedFrom']): c.add('descriptor-only')
    if any((s['source'],s['sourceId']) in bm for s in pv['sources']): c.add('brand-merge')
    if not c: c.add('other')
    g['causes']=sorted(c)
    pri=[k for k in ('carrefour-size-from-page','pack-photo-pair','descriptor-only','brand-merge','other') if k in c][0]
    g['primaryCause']=pri; excl[pri]+=1
    for k in c: over[k]+=1
rev2={p['slug'] for k in json.load(open(D+'history/rev2/catalog.v2.rev2.json'))['categories'] for p in k['products']}
now={p['slug'] for k in json.load(open(D+'catalog.v2.json'))['categories'] for p in k['products']}
absorbed=sum(len(g['mergedFrom']) for g in ch['merged'])
newslug=sum(1 for g in ch['merged'] if g['newSlug'] not in rev2)
rem=[x['slug'] for x in ch['removed']]; add=[x['slug'] for x in ch['added']]
both=sorted(set(rem)&set(add))
net_removed=len(rem)-len(both); net_added=len(add)-len(both)
net_merge=absorbed-newslug
rec=dict(
  rev2Products=len(rev2), currentProducts=len(now),
  mergeGroups=len(ch['merged']), rev2ProductsAbsorbedIntoGroups=absorbed, groupsCarryingANewSlug=newslug,
  netProductsRemovedByMerging=net_merge,
  removedListed=len(rem), addedListed=len(add), slugInBothRemovedAndAdded=both,
  netRemoved=net_removed, netAdded=net_added,
  equation=f"{len(rev2)} - {net_merge} (merges, net of {newslug} groups that carry a new slug) - {net_removed} (removed, net) + {net_added} (added, net) = {len(rev2)-net_merge-net_removed+net_added}",
  check=len(rev2)-net_merge-net_removed+net_added==len(now),
  mergeCausesExclusivePartition=dict(excl), mergeCausesOverlapping=dict(over),
  note="'mergeCausesExclusivePartition' assigns every group to exactly one primary cause (priority: Carrefour page size, pack-photo pair, descriptor-only, brand merge) and sums to the number of groups. 'mergeCausesOverlapping' counts every cause present in a group, so its values overlap and must NOT be added. Descriptor-only merges (29 in the duplicate review) were already applied in rev 2; only the ones that changed since then appear here.")
out=dict(from_='rev2 (5,801 products, 671 brands)',to='rev 3.1 (current candidate)',summary={k:len(v) for k,v in ch.items() if isinstance(v,list)},reconciliation=rec)
for k,v in ch.items():
    if k not in out and k not in ('from_','summary'): out[k]=v
json.dump(out,open(D+'changes-since-rev2.json','w'),ensure_ascii=False,indent=1)
print(json.dumps(rec,ensure_ascii=False,indent=1)); print(out['summary'])
# ---- since rev3 (this round)
o=json.load(open(D+'history/rev3/catalog.v2.rev3.json'))
O={p['slug']:(p,k['slug']) for k in o['categories'] for p in k['products']}
N={p['slug']:(p,k['slug']) for k in json.load(open(D+'catalog.v2.json'))['categories'] for p in k['products']}
O3={p['slug']:p for p in json.load(open(D+'history/rev3/provenance.rev3.json'))['products']}
byid={}
for s,p in P.items():
    for x in p['sources']: byid[(x['source'],x['sourceId'])]=s
merged=[]
for s in sorted(set(O)-set(N)):
    ids=[(x['source'],x['sourceId']) for x in O3[s]['sources']]
    tgt={byid[i] for i in ids if i in byid}
    merged.append(dict(removedSlug=s,removedName=O[s][0]['name'],mergedIntoSlug=sorted(tgt),mergedIntoName=[N[t][0]['name'] for t in sorted(tgt) if t in N],sources=[f"{a}:{b}" for a,b in ids]))
other=[s for s in set(O)&set(N) if O[s]!=N[s]]
json.dump(dict(from_='rev 3 (5,702 products)',to='rev 3.1 (5,685 products)',summary=dict(merged=len(merged),addedSlugs=len(set(N)-set(O)),categoryChanges=sum(1 for s in set(O)&set(N) if O[s][1]!=N[s][1]),fieldChanges=len(other)),
  merged=merged,fieldChanges=[dict(slug=s,changes={k:dict(was=O[s][0][k],now=N[s][0][k]) for k in O[s][0] if O[s][0][k]!=N[s][0][k]}) for s in other],
  brandsChanged=0,note='Only the 17 pack-photo-confirmed merges of review round 4. No slug was added, no category changed, no existing product touched. One kept product (mon-dessert-vanille-100-g-natilait) gained a photo: its Aziza assortment picture had been rejected, the merged Géant record has the cup photo.'),
  open(D+'changes-since-rev3.json','w'),ensure_ascii=False,indent=1)
print(len(merged),other)
for m in merged: print(m['removedSlug'],'->',m['mergedIntoSlug'])
