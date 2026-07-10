import path from 'path';
import { promises as fs } from 'fs';
import lodash from 'lodash';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const { groupBy } = lodash;
// import { confessionPathByName } from '../dataMapping';

const confessionPathByName = {
  'westminster-confession-of-faith': 'normalized-data/westminster/wcf.json',
  'westminster-larger-catechism': 'normalized-data/westminster/wlc.json',
  'westminster-shorter-catechism': 'normalized-data/westminster/wsc.json',
  'heidelberg-catechism': 'normalized-data/three-forms-of-unity/heidelberg-catechism.json',
  'canons-of-dort': 'normalized-data/three-forms-of-unity/canons-of-dort.json',
  'the-belgic-confession-of-faith': 'normalized-data/three-forms-of-unity/belgic-confession.json',
  'thirty-nine-articles-of-religion': 'normalized-data/anglican/39-articles.json',
  'martin-luthers-95-theses': 'normalized-data/reformation/95-theses.json',
  'catechism-for-young-children': 'normalized-data/miscellany/catechism-young-children.json',
};
const main = async () => {
  const contentById = await Object.entries(confessionPathByName).reduce(
    (prevPromise, [, value]) => prevPromise.then(async (acc) => {
      const pathToConfession = path.resolve(__dirname, `../${value}`);
      const fileContents = await fs.readFile(pathToConfession, 'utf8');
      const parsed = JSON.parse(fileContents);
      const asObject = parsed.content.reduce(
        (asObj, obj) => ({
          ...asObj,
          [obj.id]: obj,
        }),
        {},
      );
      return Promise.resolve({
        ...acc,
        ...asObject,
      });
    }),
    Promise.resolve({}),
  );

  const chaptersById = groupBy(
    Object.entries(contentById)
      .filter(([k]) => k.includes('-'))
      .reduce((acc, [, value]) => acc.concat([value]), []),
    (obj) => obj.parent,
  );
  await fs.writeFile(path.resolve(__dirname, '../dataMapping/content-by-id.json'), JSON.stringify(contentById));
  await fs.writeFile(path.resolve(__dirname, '../dataMapping/chapters-by-id.json'), JSON.stringify(chaptersById));

  console.info('done');
};

main();
