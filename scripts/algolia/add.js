import algoliasearch from 'algoliasearch';

const INDEX_NAME = 'aggregate_query_suggestions';
const client = algoliasearch(process.env.ALGOLIA_API_KEY, process.env.ALGOLIA_SECRET_KEY);
const index = client.initIndex(INDEX_NAME);

const documentFacets = [
  'document:95t',
  'document:wcf',
  'document:wlc',
  'document:wsc',
  'document:bcf',
  'document:hc',
  'document:cod',
  'document:39a',
];

const chapterFacets = [
  'document:95t chapter:1',
  'document:wcf chapter:1',
  'document:wlc question:1',
  'document:wsc question:1',
  'document:bcf chapter:1',
  'document:hc chapter:1',
  'document:cod article:1',
  'document:39a chapter:1',
];

const articleFacets = [
  'document:wcf chapter:1 article:2',
  'document:wcf chapter:1 question:2',
];

index
  .saveObjects(
    documentFacets
      .concat(chapterFacets)
      .concat(articleFacets),
    { autoGenerateObjectIDIfNotExist: true }
  )
  .then(({ objectIDs }) => console.log('done', objectIDs))
  .catch((e) => console.error('Some error: ', e));
