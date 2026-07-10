import algoliasearch from 'algoliasearch';

const client = algoliasearch(process.env.ALGOLIA_API_KEY, process.env.ALGOLIA_SECRET_KEY);
const bibleIndex = client.initIndex('bible verses');

const searchStr = '(undefined)';

bibleIndex
  .search(searchStr, { hitsPerPage: 1000 })
  .then(({ hits }) => hits.map(({ objectID }) => objectID))
  .then((ids) => bibleIndex.deleteObjects(ids))
  .then(({ objectIDs }) => console.log('done', objectIDs))
  .catch((e) => console.error('Some error: ', e));