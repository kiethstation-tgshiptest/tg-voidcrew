import { useBackend } from '../../tgui/backend';
import { Button, Stack } from '../../tgui/components';
import { Window } from '../../tgui/layouts';

export const HelmComputer = (props, context) => {
  const { act, data } = useBackend(context);
  return (
    <Window width={100} height={120} theme="retro">
      <Window.Content>
        <Stack vertical align="center">
          <Stack.Item>
            <Button
              icon="arrow-left"
              iconRotation={45}
              onClick={() => act('northwest')}
              />
            <Button
              icon="arrow-up"
              onClick={() => act('north')}
              />
            <Button
              icon="arrow-up"
              iconRotation={45}
              onClick={() => act('northeast')}
              />
          </Stack.Item>
        </Stack>
        <Stack vertical align="center">
          <Stack.Item>
            <Button
              icon="arrow-left"
              onClick={() => act('west')}
              />
            <Button
              icon="circle"
              />
            <Button
              icon="arrow-right"
              onClick={() => act('east')}
              />
          </Stack.Item>
        </Stack>
        <Stack vertical align="center">
          <Stack.Item>
            <Button
              icon="arrow-down"
              iconRotation={45}
              onClick={() => act('southwest')}
              />
            <Button
              icon="arrow-down"
              onClick={() => act('south')}
              />
            <Button
              icon="arrow-right"
              iconRotation={45}
              onClick={() => act('southeast')}
              />
          </Stack.Item>
        </Stack>
      </Window.Content>
    </Window>
  );
};
