import { getNode, hvigor } from '@ohos/hvigor';
import { hapTasks, OhosAppContext, OhosHapContext, OhosPluginId } from '@ohos/hvigor-ohos-plugin';

// eslint-disable-next-line @typescript-eslint/no-var-requires
const signingAcl = require('../scripts/signing_profile_acl.cjs');

interface SigningConfigLike {
  name?: string;
  material?: { profile?: string };
}

interface ProductLike {
  signingConfig?: string;
}

interface PermissionLike {
  name: string;
}

// System-key capture needs the restricted INTERCEPT_INPUT_EVENT permission.
// Declaring it without the ACL in the signing profile blocks installation of
// the whole app (9568289), so it is declared only when every product's signing
// profile grants it. RD_INTERCEPT_INPUT_EVENT_ACL=1/0 overrides the detection.
getNode(__filename).afterNodeEvaluate((node) => {
  const hapContext = node.getContext(OhosPluginId.OHOS_HAP_PLUGIN) as OhosHapContext;
  const appContext = hvigor.getRootNode().getContext(OhosPluginId.OHOS_APP_PLUGIN) as OhosAppContext;
  const appProfile = appContext.getBuildProfileOpt();
  const signingConfigs: SigningConfigLike[] = (appProfile.app.signingConfigs ?? []) as SigningConfigLike[];
  const products: ProductLike[] = (appProfile.app.products ?? []) as ProductLike[];
  const profilePaths: string[] = products
    .map((product: ProductLike): string | undefined => signingConfigs
      .find((config: SigningConfigLike): boolean => config.name === product.signingConfig)?.material?.profile)
    .filter((profilePath: string | undefined): boolean => typeof profilePath === 'string')
    .map((profilePath: string | undefined): string => profilePath as string);
  const override: boolean | undefined = signingAcl.aclOverride(process.env, 'RD_INTERCEPT_INPUT_EVENT_ACL');
  const declare: boolean = override ?? signingAcl.profilesAllowAcl(profilePaths, signingAcl.INTERCEPT_INPUT_EVENT);

  const moduleJson = hapContext.getModuleJsonOpt();
  const permissions: PermissionLike[] = (moduleJson.module.requestPermissions ?? []) as PermissionLike[];
  const kept: PermissionLike[] = permissions.filter((permission: PermissionLike): boolean =>
    permission.name !== signingAcl.INTERCEPT_INPUT_EVENT);
  if (declare) {
    kept.push({ name: signingAcl.INTERCEPT_INPUT_EVENT });
  }
  moduleJson.module.requestPermissions = kept;
  hapContext.setModuleJsonOpt(moduleJson);
  console.log('[RD] INTERCEPT_INPUT_EVENT ' + (declare ? 'declared' : 'omitted') +
    (override === undefined ? ' (signing profile ACL)' : ' (override)'));
});

export default {
  system: hapTasks, /* Built-in plugin of Hvigor. It cannot be modified. */
  plugins: []       /* Custom plugin to extend the functionality of Hvigor. */
}
